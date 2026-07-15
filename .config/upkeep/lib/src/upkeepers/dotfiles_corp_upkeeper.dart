import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class DotfilesCorpUpkeeper implements Upkeeper {
  @override
  String get id => 'dotfiles-corp';

  @override
  String get displayName => 'Private Corp Dotfiles Repository';

  String _homeDir() => Platform.environment['HOME'] ?? Directory.current.path;

  String _gitDir() => p.join(_homeDir(), '.dotfiles-corp');

  @override
  Future<bool> isSupported() async {
    return Directory(_gitDir()).existsSync();
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final home = _homeDir();
      final gitDir = _gitDir();

      // 1. Check for local modifications (dirty status)
      final statusProc = await Process.run('git', [
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
      if (statusOutput.isNotEmpty) {
        final dirtyFiles = statusOutput
            .split('\n')
            .map((line) => line.trim())
            .toList();

        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Local private dotfiles have uncommitted changes',
          details: dirtyFiles,
        );
      }

      // Fetch remote changes silently
      await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'fetch',
      ]);

      // Check if there is an upstream branch configured
      final upstreamProc = await Process.run('git', [
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
          state: UpkeepState.upToDate,
          summary: 'Private dotfiles up to date (no upstream branch tracked)',
        );
      }

      // 2. Check behind count
      final behindProc = await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-list',
        '--count',
        'HEAD..@{u}',
      ]);

      final behindCount =
          int.tryParse(behindProc.stdout.toString().trim()) ?? 0;

      // 3. Check ahead count
      final aheadProc = await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-list',
        '--count',
        '@{u}..HEAD',
      ]);

      final aheadCount = int.tryParse(aheadProc.stdout.toString().trim()) ?? 0;

      if (behindCount > 0 || aheadCount > 0) {
        final details = <String>[];
        if (behindCount > 0) {
          details.add('$behindCount new commit(s) available on remote');
        }
        if (aheadCount > 0) {
          details.add('$aheadCount local commit(s) unpushed');
        }

        final summaryList = <String>[];
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

      // Check if dirty before modifying anything
      final statusProc = await Process.run('git', [
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
      final upstreamProc = await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-parse',
        '--abbrev-ref',
        '@{u}',
      ]);

      final hasUpstream = upstreamProc.exitCode == 0;

      if (hasUpstream) {
        // Pull rebase
        final pullProc = await Process.run('git', [
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
        final pushProc = await Process.run('git', [
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
