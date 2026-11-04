import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'skills_upkeeper.dart';
import 'upkeeper.dart';

class DotfilesUpkeeper implements Upkeeper {
  final String? homeDirOverride;

  DotfilesUpkeeper({this.homeDirOverride});

  @override
  String get id => 'dotfiles';

  @override
  String get displayName => 'Personal Dotfiles Repository';

  String _homeDir() =>
      homeDirOverride ?? Platform.environment['HOME'] ?? Directory.current.path;

  String _gitDir() => p.join(_homeDir(), '.dotfiles');

  @override
  Future<bool> isSupported() async {
    return Directory(_gitDir()).existsSync();
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final home = _homeDir();
      final gitDir = _gitDir();

      // Check working tree including untracked files in un-ignored paths (-u)
      final statusProc = await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'status',
        '--porcelain',
        '-u',
      ], workingDirectory: home);
      final dirtyLines = statusProc.exitCode == 0
          ? statusProc.stdout
                .toString()
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .toList()
          : <String>[];

      // Fetch remote changes silently
      await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'fetch',
      ], workingDirectory: home);

      // Compare HEAD vs upstream
      final revProc = await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-list',
        '--count',
        'HEAD..@{u}',
      ], workingDirectory: home);

      final behindCount = revProc.exitCode == 0
          ? (int.tryParse(revProc.stdout.toString().trim()) ?? 0)
          : 0;

      return _buildStatus(
        behindCount: behindCount,
        dirtyLines: dirtyLines,
        hasUpstream: revProc.exitCode == 0,
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking dotfiles git status',
        errorMessage: e.toString(),
      );
    }
  }

  UpkeepStatus _buildStatus({
    required int behindCount,
    required List<String> dirtyLines,
    required bool hasUpstream,
  }) {
    if (behindCount > 0 || dirtyLines.isNotEmpty) {
      final summaryParts = <String>[
        if (behindCount > 0) '$behindCount commit(s) behind remote repository',
        if (dirtyLines.isNotEmpty)
          '${dirtyLines.length} uncommitted/untracked file(s) in dotfiles',
      ];
      final details = <String>[
        if (behindCount > 0)
          '$behindCount new commit(s) available on remote dotfiles',
        ...dirtyLines,
      ];
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: behindCount > 0 ? UpkeepState.outdated : UpkeepState.needsTriage,
        summary: summaryParts.join(', '),
        details: details,
        actionHint: dirtyLines.isNotEmpty ? 'dot status' : null,
      );
    }

    return UpkeepStatus(
      upkeeperId: id,
      displayName: displayName,
      state: UpkeepState.upToDate,
      summary: hasUpstream
          ? 'Dotfiles repository is up to date'
          : 'Dotfiles up to date (no upstream branch tracked)',
    );
  }

  Future<ProcessResult> _git(String home, List<String> args) => Process.run(
    'git',
    ['--git-dir=${_gitDir()}', '--work-tree=$home', ...args],
    workingDirectory: home,
  );

  /// Chooses `git pull` arguments based on local working-tree and commit state:
  /// - `--rebase --autostash` only when every locally modified file already
  ///   matches `@{u}` (e.g., another machine pushed the same skills sync),
  ///   since on a real conflict `--autostash` exits 0 with markers in `$HOME`.
  /// - `--ff-only` when there are zero local commits ahead of `@{u}`, allowing
  ///   unrelated upstream commits to advance cleanly even when `.agents/` has
  ///   un-vendored skill edits.
  /// - `--rebase` when local commits exist ahead of `@{u}`.
  Future<List<String>> _pullArgs(String home) async {
    await _git(home, ['fetch']);
    final changed = await _git(home, ['diff', '--name-only', 'HEAD']);
    final paths = changed.stdout
        .toString()
        .split('\n')
        .where((path) => path.isNotEmpty)
        .toList();
    if (changed.exitCode == 0 && paths.isNotEmpty) {
      final upstreamDiff = await _git(home, [
        'diff',
        '--quiet',
        '@{u}',
        '--',
        ...paths,
      ]);
      if (upstreamDiff.exitCode == 0) {
        return const ['pull', '--rebase', '--autostash'];
      }
    }

    final ahead = await _git(home, ['rev-list', '--count', '@{u}..HEAD']);
    if (ahead.exitCode == 0 && ahead.stdout.toString().trim() == '0') {
      return const ['pull', '--ff-only'];
    }
    return const ['pull', '--rebase'];
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final home = _homeDir();
      final pullArgs = await _pullArgs(home);
      final pullProc = await _git(home, pullArgs);

      if (pullProc.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'git ${pullArgs.join(' ')} failed',
          errorMessage: pullProc.stderr.toString(),
        );
      }

      SkillsUpkeeper(homeDirOverride: home).reconcileSymlinks(home);

      final upkeepPkgDir = p.join(home, '.config', 'upkeep');
      if (Directory(upkeepPkgDir).existsSync()) {
        await Process.run('dart', [
          'pub',
          'upgrade',
        ], workingDirectory: upkeepPkgDir);
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'Dotfiles updated successfully',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Dotfiles update failed',
        errorMessage: e.toString(),
      );
    }
  }
}
