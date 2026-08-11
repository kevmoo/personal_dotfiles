import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class DotfilesCorpUpkeeper implements Upkeeper {
  @override
  String get id => 'dotfiles-corp';

  @override
  String get displayName => 'Private Corp Dotfiles Repository';

  final bool? isCloudtopOverride;
  final String Function()? homeDirOverride;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  processRunner;

  DotfilesCorpUpkeeper({
    this.isCloudtopOverride,
    this.homeDirOverride,
    this.processRunner,
  });

  String _homeDir() => homeDirOverride != null
      ? homeDirOverride!()
      : (Platform.environment['HOME'] ?? Directory.current.path);

  String _gitDir() => p.join(_homeDir(), '.dotfiles-corp');

  Future<ProcessResult> _run(String executable, List<String> arguments) {
    if (processRunner != null) {
      return processRunner!(executable, arguments);
    }
    return Process.run(executable, arguments);
  }

  @override
  Future<bool> isSupported() async {
    if (isCloudtopOverride != null) return isCloudtopOverride!;
    if (Platform.isLinux) {
      if (Directory('/google/src').existsSync() ||
          File('/etc/glinux-release').existsSync()) {
        return true;
      }
      try {
        final result = await _run('which', ['gcertstatus']);
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  UpkeepStatus _status(
    UpkeepState state,
    String summary, {
    String? errorMessage,
    List<String> details = const [],
  }) => UpkeepStatus(
    upkeeperId: id,
    displayName: displayName,
    state: state,
    summary: summary,
    errorMessage: errorMessage,
    details: details,
  );

  Future<ProcessResult> _corpGit(
    String gitDir,
    String home,
    List<String> args,
  ) => _run('git', ['--git-dir=$gitDir', '--work-tree=$home', ...args]);

  @override
  Future<UpkeepStatus> check() async {
    try {
      final home = _homeDir();
      final gitDir = _gitDir();

      if (!Directory(gitDir).existsSync()) {
        return _status(
          UpkeepState.error,
          'Private dotfiles directory not found at $gitDir',
          errorMessage:
              'Run dotcorp setup to initialize the private repository.',
        );
      }

      // 1. Check for local modifications (dirty status)
      final statusProc = await _corpGit(gitDir, home, [
        'status',
        '--porcelain',
      ]);
      if (statusProc.exitCode != 0) {
        return _status(
          UpkeepState.error,
          'Error checking git status',
          errorMessage: statusProc.stderr.toString(),
        );
      }

      final dirtyFiles = _parseDirtyFiles(statusProc.stdout.toString());
      final isDirty = dirtyFiles.isNotEmpty;

      // 2. Fetch remote changes
      final fetchProc = await _corpGit(gitDir, home, ['fetch']);
      if (fetchProc.exitCode != 0) {
        return switch (isDirty) {
          true => _status(
            UpkeepState.outdated,
            'Local private dotfiles have uncommitted changes (Fetch failed)',
            errorMessage: fetchProc.stderr.toString(),
            details: dirtyFiles,
          ),
          false => _status(
            UpkeepState.error,
            'Error fetching remote updates for private dotfiles',
            errorMessage: fetchProc.stderr.toString(),
          ),
        };
      }

      // Check if there is an upstream branch configured
      final upstreamProc = await _corpGit(gitDir, home, [
        'rev-parse',
        '--abbrev-ref',
        '@{u}',
      ]);
      if (upstreamProc.exitCode != 0) {
        return switch (isDirty) {
          true => _status(
            UpkeepState.outdated,
            'Local private dotfiles have uncommitted changes (No upstream branch)',
            details: dirtyFiles,
          ),
          false => _status(
            UpkeepState.upToDate,
            'Private dotfiles up to date (no upstream branch tracked)',
          ),
        };
      }

      // 3 & 4. Behind/ahead counts against upstream
      final behindCount = _countOutput(
        await _corpGit(gitDir, home, ['rev-list', '--count', 'HEAD..@{u}']),
      );
      final aheadCount = _countOutput(
        await _corpGit(gitDir, home, ['rev-list', '--count', '@{u}..HEAD']),
      );

      final (:details, :summaryParts) = _syncDrift(
        isDirty: isDirty,
        dirtyFiles: dirtyFiles,
        behindCount: behindCount,
        aheadCount: aheadCount,
      );
      if (summaryParts.isEmpty) {
        return _status(
          UpkeepState.upToDate,
          'Private dotfiles repository is up to date',
        );
      }
      return _status(
        UpkeepState.outdated,
        'Private dotfiles out of sync: ${summaryParts.join(', ')}',
        details: details,
      );
    } catch (e) {
      return _status(
        UpkeepState.error,
        'Exception checking private dotfiles git status',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final home = _homeDir();
      final gitDir = _gitDir();

      if (!Directory(gitDir).existsSync()) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Private dotfiles directory not found at $gitDir',
        );
      }

      // Check if dirty before modifying anything
      final statusProc = await _run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'status',
        '--porcelain',
      ]);

      if (statusProc.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Error checking git status before update',
          errorMessage: statusProc.stderr.toString(),
        );
      }

      if (statusProc.stdout.toString().trim().isNotEmpty) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Cannot update: local private dotfiles have uncommitted changes. Please commit or stash them first.',
        );
      }

      // Check upstream
      final upstreamProc = await _run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-parse',
        '--abbrev-ref',
        '@{u}',
      ]);

      final hasUpstream = upstreamProc.exitCode == 0;

      if (hasUpstream) {
        // Pull rebase
        final pullProc = await _run('git', [
          '--git-dir=$gitDir',
          '--work-tree=$home',
          'pull',
          '--rebase',
        ]);

        if (pullProc.exitCode != 0) {
          return UpkeepResult(
            upkeeperId: id,
            displayName: displayName,
            success: false,
            message: 'git pull --rebase failed on private dotfiles',
            errorMessage: pullProc.stderr.toString(),
          );
        }

        // Push
        final pushProc = await _run('git', [
          '--git-dir=$gitDir',
          '--work-tree=$home',
          'push',
        ]);

        if (pushProc.exitCode != 0) {
          return UpkeepResult(
            upkeeperId: id,
            displayName: displayName,
            success: false,
            message: 'git push failed on private dotfiles',
            errorMessage: pushProc.stderr.toString(),
          );
        }
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'Private dotfiles updated successfully',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Private dotfiles update failed',
        errorMessage: e.toString(),
      );
    }
  }
}

/// Trimmed non-empty lines of `git status --porcelain` output.
List<String> _parseDirtyFiles(String statusStdout) {
  final output = statusStdout.trim();
  if (output.isEmpty) return const [];
  return output.split('\n').map((line) => line.trim()).toList();
}

/// Integer stdout of a `rev-list --count` invocation; 0 when unparseable.
int _countOutput(ProcessResult result) =>
    int.tryParse(result.stdout.toString().trim()) ?? 0;

/// Human-readable description of how the repo diverges from upstream.
({List<String> details, List<String> summaryParts}) _syncDrift({
  required bool isDirty,
  required List<String> dirtyFiles,
  required int behindCount,
  required int aheadCount,
}) {
  final details = <String>[];
  final summaryParts = <String>[];
  if (isDirty) {
    details.add('Local modifications:');
    details.addAll(dirtyFiles.map((f) => '  $f'));
    summaryParts.add('dirty');
  }
  if (behindCount > 0) {
    details.add('$behindCount new commit(s) available on remote');
    summaryParts.add('$behindCount behind');
  }
  if (aheadCount > 0) {
    details.add('$aheadCount local commit(s) unpushed');
    summaryParts.add('$aheadCount ahead');
  }
  return (details: details, summaryParts: summaryParts);
}
