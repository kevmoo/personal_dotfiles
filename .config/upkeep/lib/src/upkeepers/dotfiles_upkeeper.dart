import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
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

      if (behindCount > 0 || dirtyLines.isNotEmpty) {
        final summaryParts = <String>[
          if (behindCount > 0)
            '$behindCount commit(s) behind remote repository',
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
          state: UpkeepState.outdated,
          summary: summaryParts.join(', '),
          details: details,
        );
      }

      if (revProc.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Dotfiles up to date (no upstream branch tracked)',
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'Dotfiles repository is up to date',
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

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final home = _homeDir();
      final gitDir = _gitDir();

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
          message: 'git pull --rebase failed',
          errorMessage: pullProc.stderr.toString(),
        );
      }

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
