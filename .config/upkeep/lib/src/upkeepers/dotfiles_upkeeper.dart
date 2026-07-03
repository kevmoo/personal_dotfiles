import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class DotfilesUpkeeper implements Upkeeper {
  @override
  String get id => 'dotfiles';

  @override
  String get displayName => 'Personal Dotfiles Repository';

  String _homeDir() => Platform.environment['HOME'] ?? Directory.current.path;

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

      // Fetch remote changes silently
      await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'fetch',
      ]);

      // Compare HEAD vs upstream
      final revProc = await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'rev-list',
        '--count',
        'HEAD..@{u}',
      ]);

      if (revProc.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Dotfiles up to date (no upstream branch tracked)',
        );
      }

      final countStr = revProc.stdout.toString().trim();
      final behindCount = int.tryParse(countStr) ?? 0;

      if (behindCount > 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: '$behindCount commit(s) behind remote repository',
          details: ['$behindCount new commit(s) available on remote dotfiles'],
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
