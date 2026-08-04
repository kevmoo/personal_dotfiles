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

  bool _isGitRepo(Directory? dir) =>
      dir != null && Directory(p.join(dir.path, '.git')).existsSync();

  Directory? _resolveFromEnv() {
    for (final envVar in ['FLUTTER_ROOT', 'FLUTTER_HOME']) {
      final path = Platform.environment[envVar];
      if (path != null && path.isNotEmpty) {
        final dir = Directory(path);
        if (_isGitRepo(dir)) return dir;
      }
    }
    return null;
  }

  Future<Directory?> _resolveFromPath() async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final res = await _processRunner(cmd, ['flutter']);
      if (res.exitCode != 0) return null;

      final binPath = res.stdout.toString().split('\n').first.trim();
      if (binPath.isEmpty) return null;

      final file = File(binPath);
      if (!file.existsSync()) return null;

      final rootPath = p.dirname(p.dirname(file.resolveSymbolicLinksSync()));
      final dir = Directory(rootPath);
      return _isGitRepo(dir) ? dir : null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _resolveFlutterDir() async {
    if (_flutterDirOverride != null) {
      return _isGitRepo(_flutterDirOverride) ? _flutterDirOverride : null;
    }

    final fromEnv = _resolveFromEnv();
    if (fromEnv != null) return fromEnv;

    final fromPath = await _resolveFromPath();
    if (fromPath != null) return fromPath;

    final defaultDir = Directory(p.join(_homeDir(), 'github', 'flutter'));
    return _isGitRepo(defaultDir) ? defaultDir : null;
  }

  @override
  Future<bool> isSupported() async {
    final dir = await _resolveFlutterDir();
    return dir != null;
  }

  Future<String?> _currentBranch(Directory dir) async {
    final res = await _processRunner('git', [
      '-C',
      dir.path,
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ]);
    return res.exitCode == 0 ? res.stdout.toString().trim() : null;
  }

  Future<int> _commitsBehind(Directory dir, String branch) async {
    final res = await _processRunner('git', [
      '-C',
      dir.path,
      'rev-list',
      '--count',
      'HEAD..origin/$branch',
    ]);
    return int.tryParse(res.stdout.toString().trim()) ?? 0;
  }

  Future<({String label, int hours})> _headAge(Directory dir) async {
    final logRes = await _processRunner('git', [
      '-C',
      dir.path,
      'log',
      '-1',
      '--format=%ct',
      'HEAD',
    ]);
    final epochSecs = int.tryParse(logRes.stdout.toString().trim());
    if (epochSecs == null) return (label: 'unknown age', hours: 0);

    final commitTime = DateTime.fromMillisecondsSinceEpoch(epochSecs * 1000);
    final diff = _nowProvider().difference(commitTime);
    final hours = diff.inHours;
    final days = diff.inDays;
    final label = days > 0
        ? '$days day${days == 1 ? '' : 's'}'
        : '$hours hour${hours == 1 ? '' : 's'}';
    return (label: label, hours: hours);
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

      final branch = await _currentBranch(repoDir);
      if (branch == null) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Failed to determine Flutter repo branch',
        );
      }

      if (branch != 'master' && branch != 'main') {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Not on master/main branch (current: $branch)',
          details: ['Expected master or main branch, but found "$branch".'],
        );
      }

      await _processRunner('git', [
        '-C',
        repoDir.path,
        'fetch',
        '--quiet',
        'origin',
        branch,
      ]);

      final behind = await _commitsBehind(repoDir, branch);
      final age = await _headAge(repoDir);

      if (behind > 0 || age.hours > 72) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary:
              '$branch is $behind commit${behind == 1 ? '' : 's'} behind origin/$branch (${age.label} old)',
          details: [
            'Branch $branch is trailing origin/$branch by $behind commit(s).',
            'Local checkout HEAD commit is ${age.label} old.',
          ],
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary:
            'Up to date on $branch (0 commits behind, HEAD is ${age.label} old)',
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

  Future<({bool clean, String? error})> _verifyCleanWorkingTree(
    Directory dir,
  ) async {
    final statusRes = await _processRunner('git', [
      '-C',
      dir.path,
      'status',
      '--porcelain',
    ]);
    if (statusRes.exitCode != 0) {
      return (clean: false, error: statusRes.stderr.toString().trim());
    }
    if (statusRes.stdout.toString().trim().isNotEmpty) {
      return (clean: false, error: null);
    }
    return (clean: true, error: null);
  }

  Future<({bool success, String targetBranch, String? error})>
  _ensureDefaultBranch(Directory dir, String current) async {
    if (current == 'master' || current == 'main') {
      return (success: true, targetBranch: current, error: null);
    }

    var res = await _processRunner('git', [
      '-C',
      dir.path,
      'checkout',
      'master',
    ]);
    if (res.exitCode == 0) {
      return (success: true, targetBranch: 'master', error: null);
    }

    res = await _processRunner('git', ['-C', dir.path, 'checkout', 'main']);
    if (res.exitCode == 0) {
      return (success: true, targetBranch: 'main', error: null);
    }

    return (
      success: false,
      targetBranch: current,
      error: res.stderr.toString().trim(),
    );
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

      final status = await _verifyCleanWorkingTree(repoDir);
      if (!status.clean) {
        if (status.error != null) {
          return UpkeepResult(
            upkeeperId: id,
            displayName: displayName,
            success: false,
            message: 'Failed to inspect Flutter working directory status',
            errorMessage: status.error,
          );
        }
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Cannot update Flutter repository: uncommitted local changes exist',
        );
      }

      final branch = await _currentBranch(repoDir) ?? '';
      final checkout = await _ensureDefaultBranch(repoDir, branch);
      if (!checkout.success) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message:
              'Failed to check out master or main branch in Flutter repository',
          errorMessage: checkout.error,
        );
      }

      final target = checkout.targetBranch;
      final fetchRes = await _processRunner('git', [
        '-C',
        repoDir.path,
        'pull',
        '--ff-only',
        'origin',
        target,
      ]);
      if (fetchRes.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed fast-forward pull on Flutter repository ($target)',
          errorMessage: fetchRes.stderr.toString().trim(),
        );
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'Successfully updated Flutter repository on branch $target',
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
