import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class SkillsUpkeeper implements Upkeeper {
  @override
  String get id => 'skills';

  @override
  String get displayName => 'Agent Skills';

  @override
  Future<bool> isSupported() async {
    try {
      final result = await Process.run('which', ['npx']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _homeDir() => Platform.environment['HOME'] ?? Directory.current.path;

  @override
  Future<UpkeepStatus> check() async {
    try {
      final result = await Process.run('npx', ['skills', 'check']);
      if (result.exitCode != 0) {
        // Fallback: check if .agents directory exists
        final agentsDir = Directory(p.join(_homeDir(), '.agents'));
        if (!agentsDir.existsSync()) {
          return UpkeepStatus(
            upkeeperId: id,
            displayName: displayName,
            state: UpkeepState.skipped,
            summary: 'No .agents directory found',
          );
        }
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Agent skills present (check skipped)',
        );
      }

      final output = result.stdout.toString().trim();
      if (output.contains('outdated') || output.contains('update available')) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Agent skills have updates available',
          details: [output],
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'Agent skills up to date',
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking agent skills',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      // 1. Run global skills update (npx skills update -g)
      final globalProc = await Process.run('npx', ['skills', 'update', '-g']);
      final globalSuccess = globalProc.exitCode == 0;

      // 2. Run local skills update if .agents directory exists
      final home = _homeDir();
      bool localSuccess = true;
      if (Directory(p.join(home, '.agents')).existsSync()) {
        final localProc = await Process.run('npx', [
          'skills',
          'update',
        ], workingDirectory: home);
        localSuccess = localProc.exitCode == 0;
      }

      if (globalSuccess && localSuccess) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message: 'Successfully updated agent skills (global and local)',
        );
      } else {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to update some agent skills',
          errorMessage: 'Global output: ${globalProc.stderr.toString().trim()}',
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Failed to run npx skills update',
        errorMessage: e.toString(),
      );
    }
  }
}
