import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

typedef FlutterRepoProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class FlutterRepoUpkeeper implements Upkeeper {
  final FlutterRepoProcessRunner _processRunner;
  final Directory? _flutterDirOverride;
  final DateTime Function() _nowProvider;

  FlutterRepoUpkeeper({
    FlutterRepoProcessRunner? processRunner,
    Directory? overrideFlutterDir,
    DateTime Function()? nowProvider,
  }) : _processRunner = processRunner ?? Process.run,
       _flutterDirOverride = overrideFlutterDir,
       _nowProvider = nowProvider ?? DateTime.now;

  @override
  String get id => 'flutter-repo-outdated';

  @override
  String get displayName => 'Flutter Repository (~/github/flutter)';

  String _homeDir() =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  Future<Directory?> _resolveFlutterDir() async {
    if (_flutterDirOverride != null) {
      if (Directory(p.join(_flutterDirOverride.path, '.git')).existsSync()) {
        return _flutterDirOverride;
      }
      return null;
    }

    // 1. Check standard environment variables (FLUTTER_ROOT or FLUTTER_HOME)
    for (final envVar in ['FLUTTER_ROOT', 'FLUTTER_HOME']) {
      final path = Platform.environment[envVar];
      if (path != null && path.isNotEmpty) {
        final dir = Directory(path);
        if (Directory(p.join(dir.path, '.git')).existsSync()) {
          return dir;
        }
      }
    }

    // 2. Look for flutter binary in PATH using process runner
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final whichRes = await _processRunner(cmd, ['flutter']);
      if (whichRes.exitCode == 0) {
        final binPath = whichRes.stdout.toString().split('\n').first.trim();
        if (binPath.isNotEmpty) {
          final file = File(binPath);
          if (file.existsSync()) {
            final realPath = file.resolveSymbolicLinksSync();
            final rootPath = p.dirname(p.dirname(realPath));
            final dir = Directory(rootPath);
            if (Directory(p.join(dir.path, '.git')).existsSync()) {
              return dir;
            }
          }
        }
      }
    } catch (_) {
      // Ignore process failure or missing binary
    }

    // 3. Fallback to default check in ~/github/flutter
    final defaultDir = Directory(p.join(_homeDir(), 'github', 'flutter'));
    if (Directory(p.join(defaultDir.path, '.git')).existsSync()) {
      return defaultDir;
    }

    return null;
  }

  @override
  Future<bool> isSupported() async {
    final dir = await _resolveFlutterDir();
    return dir != null;
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final repoDir = await _resolveFlutterDir();
      if (repoDir == null || !repoDir.existsSync()) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.skipped,
          summary: 'Flutter repository not found in environment, PATH, or ~/github/flutter',
        );
      }

      // Check current branch
      final branchRes = await _processRunner('git', [
        '-C',
        repoDir.path,
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      if (branchRes.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Failed to determine Flutter repo branch',
          errorMessage: branchRes.stderr.toString().trim(),
        );
      }

      final branch = branchRes.stdout.toString().trim();
      if (branch != 'master' && branch != 'main') {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Not on master/main branch (current: $branch)',
          details: ['Expected master or main branch, but found "$branch".'],
        );
      }

      // Attempt silent fetch of remote branch
      await _processRunner('git', [
        '-C',
        repoDir.path,
        'fetch',
        '--quiet',
        'origin',
        branch,
      ]);

      // Check commits behind origin/master or origin/main
      final countRes = await _processRunner('git', [
        '-C',
        repoDir.path,
        'rev-list',
        '--count',
        'HEAD..origin/$branch',
      ]);
      final countStr = countRes.stdout.toString().trim();
      final commitsBehind = int.tryParse(countStr) ?? 0;

      // Get HEAD commit timestamp to measure age / days behind
      final logRes = await _processRunner('git', [
        '-C',
        repoDir.path,
        'log',
        '-1',
        '--format=%ct',
        'HEAD',
      ]);
      final tsStr = logRes.stdout.toString().trim();
      final epochSecs = int.tryParse(tsStr);

      String ageStr = 'unknown age';
      int hoursBehind = 0;
      if (epochSecs != null) {
        final commitTime = DateTime.fromMillisecondsSinceEpoch(
          epochSecs * 1000,
        );
        final diff = _nowProvider().difference(commitTime);
        hoursBehind = diff.inHours;
        final days = diff.inDays;
        ageStr = days > 0
            ? '$days day${days == 1 ? '' : 's'}'
            : '$hoursBehind hour${hoursBehind == 1 ? '' : 's'}';
      }

      if (commitsBehind > 0 || hoursBehind > 72) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary:
              '$branch is $commitsBehind commit${commitsBehind == 1 ? '' : 's'} behind origin/$branch ($ageStr old)',
          details: [
            'Branch $branch is trailing origin/$branch by $commitsBehind commit(s).',
            'Local checkout HEAD commit is $ageStr old.',
          ],
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary:
            'Up to date on $branch (0 commits behind, HEAD is $ageStr old)',
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking Flutter repository status',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final repoDir = await _resolveFlutterDir();
      if (repoDir == null || !repoDir.existsSync()) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Flutter repo directory could not be resolved',
        );
      }

      // Check if working tree is clean
      final statusRes = await _processRunner('git', [
        '-C',
        repoDir.path,
        'status',
        '--porcelain',
      ]);
      if (statusRes.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to inspect Flutter working directory status',
          errorMessage: statusRes.stderr.toString().trim(),
        );
      }

      if (statusRes.stdout.toString().trim().isNotEmpty) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Cannot update Flutter repository: uncommitted local changes exist',
        );
      }

      // Check out master or main if not currently on it
      final branchRes = await _processRunner('git', [
        '-C',
        repoDir.path,
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      var currentBranch = branchRes.stdout.toString().trim();
      if (currentBranch != 'master' && currentBranch != 'main') {
        // Try checking out master first, then main
        var checkoutRes = await _processRunner('git', [
          '-C',
          repoDir.path,
          'checkout',
          'master',
        ]);
        if (checkoutRes.exitCode == 0) {
          currentBranch = 'master';
        } else {
          checkoutRes = await _processRunner('git', [
            '-C',
            repoDir.path,
            'checkout',
            'main',
          ]);
          if (checkoutRes.exitCode == 0) {
            currentBranch = 'main';
          } else {
            return UpkeepResult(
              upkeeperId: id,
              displayName: displayName,
              success: false,
              message: 'Failed to check out master or main branch in Flutter repository',
              errorMessage: checkoutRes.stderr.toString().trim(),
            );
          }
        }
      }

      // Perform fast-forward pull and fetch
      final fetchRes = await _processRunner('git', [
        '-C',
        repoDir.path,
        'pull',
        '--ff-only',
        'origin',
        currentBranch,
      ]);
      if (fetchRes.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message:
              'Failed fast-forward pull on Flutter repository ($currentBranch)',
          errorMessage: fetchRes.stderr.toString().trim(),
        );
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message:
            'Successfully updated Flutter repository on branch $currentBranch',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Exception updating Flutter repository',
        errorMessage: e.toString(),
      );
    }
  }
}
