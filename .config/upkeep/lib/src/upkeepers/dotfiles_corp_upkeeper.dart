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

  @override
  Future<UpkeepStatus> check() async {
    try {
      final home = _homeDir();
      final gitDir = _gitDir();

      if (!Directory(gitDir).existsSync()) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Private dotfiles directory not found at $gitDir',
          errorMessage:
              'Run dotcorp setup to initialize the private repository.',
        );
      }

      // 1. Check for local modifications (dirty status)
      final statusProc = await _run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'status',
        '--porcelain',
      ]);

      if (statusProc.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Error checking git status',
          errorMessage: statusProc.stderr.toString(),
        );
      }

      final statusOutput = statusProc.stdout.toString().trim();
      final isDirty = statusOutput.isNotEmpty;
      final dirtyFiles = isDirty
          ? statusOutput.split('\n').map((line) => line.trim()).toList()
          : <String>[];

      // 2. Fetch remote changes
      final fetchProc = await _run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'fetch',
      ]);

      if (fetchProc.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: isDirty ? UpkeepState.outdated : UpkeepState.error,
          summary: isDirty
              ? 'Local private dotfiles have uncommitted changes (Fetch failed)'
              : 'Error fetching remote updates for private dotfiles',
          errorMessage: fetchProc.stderr.toString(),
          details: isDirty ? dirtyFiles : const [],
        );
      }

      // Check if there is an upstream branch configured
      final upstreamProc = await _run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-parse',
        '--abbrev-ref',
        '@{u}',
      ]);

      if (upstreamProc.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: isDirty ? UpkeepState.outdated : UpkeepState.upToDate,
          summary: isDirty
              ? 'Local private dotfiles have uncommitted changes (No upstream branch)'
              : 'Private dotfiles up to date (no upstream branch tracked)',
          details: isDirty ? dirtyFiles : const [],
        );
      }

      // 3. Check behind count
      final behindProc = await _run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-list',
        '--count',
        'HEAD..@{u}',
      ]);

      final behindCount =
          int.tryParse(behindProc.stdout.toString().trim()) ?? 0;

      // 4. Check ahead count
      final aheadProc = await _run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-list',
        '--count',
        '@{u}..HEAD',
      ]);

      final aheadCount = int.tryParse(aheadProc.stdout.toString().trim()) ?? 0;

      if (isDirty || behindCount > 0 || aheadCount > 0) {
        final details = <String>[];
        if (isDirty) {
          details.add('Local modifications:');
          details.addAll(dirtyFiles.map((f) => '  $f'));
        }
        if (behindCount > 0) {
          details.add('$behindCount new commit(s) available on remote');
        }
        if (aheadCount > 0) {
          details.add('$aheadCount local commit(s) unpushed');
        }

        final summaryList = <String>[];
        if (isDirty) summaryList.add('dirty');
        if (behindCount > 0) summaryList.add('$behindCount behind');
        if (aheadCount > 0) summaryList.add('$aheadCount ahead');

        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Private dotfiles out of sync: ${summaryList.join(', ')}',
          details: details,
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'Private dotfiles repository is up to date',
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking private dotfiles git status',
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
