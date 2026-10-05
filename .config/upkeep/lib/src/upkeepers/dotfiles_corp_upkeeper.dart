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

  String _hookPath(String home) =>
      p.join(home, '.local', 'bin', 'dotcorp-upkeep-hook');

  Future<ProcessResult> _run(String executable, List<String> arguments) {
    if (processRunner != null) {
      return processRunner!(executable, arguments);
    }
    return Process.run(executable, arguments);
  }

  Future<
    ({
      bool isOutdated,
      bool isError,
      List<String> details,
      String? errorMessage,
    })
  >
  _checkHook(String home) async {
    final hook = _hookPath(home);
    if (!File(hook).existsSync()) {
      return (
        isOutdated: false,
        isError: false,
        details: const <String>[],
        errorMessage: null,
      );
    }
    final proc = await _run(hook, ['check']);
    final output = '${proc.stdout}\n${proc.stderr}'.trim();
    final lines = output.isEmpty
        ? const <String>[]
        : output
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
    if (proc.exitCode == 0) {
      return (
        isOutdated: false,
        isError: false,
        details: lines,
        errorMessage: null,
      );
    }
    if (proc.exitCode == 10) {
      return (
        isOutdated: true,
        isError: false,
        details: lines,
        errorMessage: null,
      );
    }
    return (
      isOutdated: false,
      isError: true,
      details: lines,
      errorMessage: output.isEmpty
          ? 'Hook exited with code ${proc.exitCode}'
          : output,
    );
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

  UpkeepResult _result(bool success, String message, {String? errorMessage}) =>
      UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: success,
        message: message,
        errorMessage: errorMessage,
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

      final statusOut = statusProc.stdout.toString().trim();
      final dirtyFiles = statusOut.isEmpty
          ? const <String>[]
          : statusOut.split('\n').map((l) => l.trim()).toList();
      final isDirty = dirtyFiles.isNotEmpty;

      final hookStatus = await _checkHook(home);
      if (hookStatus.isError) {
        return _status(
          UpkeepState.error,
          'Private dotfiles hook check failed',
          errorMessage: hookStatus.errorMessage,
          details: hookStatus.details,
        );
      }

      final fetchProc = await _corpGit(gitDir, home, ['fetch']);
      if (fetchProc.exitCode != 0) {
        final stderrStr = fetchProc.stderr.toString();
        return isDirty
            ? _status(
                UpkeepState.outdated,
                'Local private dotfiles have uncommitted changes (Fetch failed)',
                errorMessage: stderrStr,
                details: dirtyFiles,
              )
            : _status(
                UpkeepState.error,
                'Error fetching remote updates for private dotfiles',
                errorMessage: stderrStr,
              );
      }

      final upstream = await _upstreamCounts(gitDir, home);
      return _buildSyncStatus(dirtyFiles, hookStatus, upstream);
    } catch (e) {
      return _status(
        UpkeepState.error,
        'Exception checking private dotfiles git status',
        errorMessage: e.toString(),
      );
    }
  }

  UpkeepStatus _buildSyncStatus(
    List<String> dirtyFiles,
    ({
      bool isError,
      bool isOutdated,
      String? errorMessage,
      List<String> details,
    })
    hookStatus,
    ({bool hasUpstream, int behind, int ahead}) upstream,
  ) {
    final isDirty = dirtyFiles.isNotEmpty;
    if (!upstream.hasUpstream && isDirty && !hookStatus.isOutdated) {
      return _status(
        UpkeepState.outdated,
        'Local private dotfiles have uncommitted changes (No upstream branch)',
        details: dirtyFiles,
      );
    }

    final details = <String>[
      if (isDirty) ...[
        'Local modifications:',
        ...dirtyFiles.map((f) => '  $f'),
      ],
      if (upstream.behind > 0)
        '${upstream.behind} new commit(s) available on remote',
      if (upstream.ahead > 0) '${upstream.ahead} local commit(s) unpushed',
      if (hookStatus.isOutdated) ...hookStatus.details,
    ];
    final summaryParts = <String>[
      if (isDirty) 'dirty',
      if (upstream.behind > 0) '${upstream.behind} behind',
      if (upstream.ahead > 0) '${upstream.ahead} ahead',
      if (hookStatus.isOutdated) 'hook outdated',
    ];
    if (summaryParts.isEmpty) {
      final msg = upstream.hasUpstream
          ? 'Private dotfiles repository is up to date'
          : 'Private dotfiles up to date (no upstream branch tracked)';
      return _status(UpkeepState.upToDate, msg);
    }
    final suffix = upstream.hasUpstream ? '' : ' (No upstream branch)';
    return _status(
      UpkeepState.outdated,
      'Private dotfiles out of sync: ${summaryParts.join(', ')}$suffix',
      details: details,
    );
  }

  Future<({bool hasUpstream, int behind, int ahead})> _upstreamCounts(
    String gitDir,
    String home,
  ) async {
    final upstreamProc = await _corpGit(gitDir, home, [
      'rev-parse',
      '--abbrev-ref',
      '@{u}',
    ]);
    if (upstreamProc.exitCode != 0) {
      return (hasUpstream: false, behind: 0, ahead: 0);
    }
    final behind = _countOutput(
      await _corpGit(gitDir, home, ['rev-list', '--count', 'HEAD..@{u}']),
    );
    final ahead = _countOutput(
      await _corpGit(gitDir, home, ['rev-list', '--count', '@{u}..HEAD']),
    );
    return (hasUpstream: true, behind: behind, ahead: ahead);
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final home = _homeDir();
      final gitDir = _gitDir();
      final hook = _hookPath(home);
      final hasHook = File(hook).existsSync();

      if (!Directory(gitDir).existsSync()) {
        return _result(
          false,
          'Private dotfiles directory not found at $gitDir',
        );
      }

      final statusProc = await _corpGit(gitDir, home, [
        'status',
        '--porcelain',
      ]);
      if (statusProc.exitCode != 0) {
        return _result(
          false,
          'Error checking git status before update',
          errorMessage: statusProc.stderr.toString(),
        );
      }

      if (statusProc.stdout.toString().trim().isNotEmpty) {
        return hasHook
            ? await _runHookUpdate(
                hook,
                successMsg: 'Private dotfiles hook updated (git pull/push skipped due to uncommitted changes)',
              )
            : _result(
                false,
                'Cannot update: local private dotfiles have uncommitted changes. Please commit or stash them first.',
              );
      }

      final syncFailure = await _pullAndPushIfUpstream(gitDir, home);
      if (syncFailure != null) return syncFailure;

      if (hasHook) {
        return await _runHookUpdate(
          hook,
          successMsg: 'Private dotfiles updated successfully',
        );
      }
      return _result(true, 'Private dotfiles updated successfully');
    } catch (e) {
      return _result(
        false,
        'Private dotfiles update failed',
        errorMessage: e.toString(),
      );
    }
  }

  Future<UpkeepResult?> _pullAndPushIfUpstream(
    String gitDir,
    String home,
  ) async {
    final upstreamProc = await _corpGit(gitDir, home, [
      'rev-parse',
      '--abbrev-ref',
      '@{u}',
    ]);
    if (upstreamProc.exitCode != 0) return null;

    final pullProc = await _corpGit(gitDir, home, ['pull', '--rebase']);
    if (pullProc.exitCode != 0) {
      return _result(
        false,
        'git pull --rebase failed on private dotfiles',
        errorMessage: pullProc.stderr.toString(),
      );
    }

    final pushProc = await _corpGit(gitDir, home, ['push']);
    if (pushProc.exitCode != 0) {
      return _result(
        false,
        'git push failed on private dotfiles',
        errorMessage: pushProc.stderr.toString(),
      );
    }
    return null;
  }

  Future<UpkeepResult> _runHookUpdate(
    String hook, {
    required String successMsg,
  }) async {
    final hookProc = await _run(hook, ['update']);
    if (hookProc.exitCode != 0) {
      return _result(
        false,
        'Private dotfiles hook update failed',
        errorMessage: '${hookProc.stdout}\n${hookProc.stderr}'.trim(),
      );
    }
    return _result(true, successMsg);
  }
}

/// Integer stdout of a `rev-list --count` invocation; 0 when unparseable.
int _countOutput(ProcessResult result) =>
    int.tryParse(result.stdout.toString().trim()) ?? 0;
