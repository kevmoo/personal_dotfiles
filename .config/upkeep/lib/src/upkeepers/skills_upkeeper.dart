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
      final home = _homeDir();
      final result = await Process.run('npx', ['skills', 'check']);
      if (result.exitCode != 0) {
        // Fallback: check if .agents directory exists
        final agentsDir = Directory(p.join(home, '.agents'));
        if (!agentsDir.existsSync()) {
          return UpkeepStatus(
            upkeeperId: id,
            displayName: displayName,
            state: UpkeepState.skipped,
            summary: 'No .agents directory found',
          );
        }

        if (_needsReconciliation(home)) {
          return UpkeepStatus(
            upkeeperId: id,
            displayName: displayName,
            state: UpkeepState.outdated,
            summary: 'Agent skills symlinks need reconciliation',
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

      if (_needsReconciliation(home)) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Agent skills symlinks need reconciliation',
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

      // 3. Reconcile symlinks in ~/.claude/skills/
      _reconcileSymlinks(home);

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

  bool _needsReconciliation(String home) {
    final claudeSkillsDir = Directory(p.join(home, '.claude', 'skills'));
    final agentsSkillsDir = Directory(p.join(home, '.agents', 'skills'));
    if (!claudeSkillsDir.existsSync() || !agentsSkillsDir.existsSync()) {
      return false;
    }

    // A. Check for missing relative links
    for (final entity in agentsSkillsDir.listSync()) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        final targetLink = Link(p.join(claudeSkillsDir.path, name));
        if (FileSystemEntity.typeSync(targetLink.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          return true;
        }
      }
    }

    // B. Check for dangling non-GC links
    for (final entity in claudeSkillsDir.listSync(followLinks: false)) {
      if (entity is Link) {
        final name = p.basename(entity.path);
        if (name.startsWith('core.gc-')) continue;

        // Check if link is dangling (target doesn't exist)
        final targetPath = entity.targetSync();
        final resolvedTarget = p.isAbsolute(targetPath)
            ? targetPath
            : p.normalize(p.join(claudeSkillsDir.path, targetPath));

        if (FileSystemEntity.typeSync(resolvedTarget) ==
            FileSystemEntityType.notFound) {
          return true;
        }
      }
    }

    return false;
  }

  void _reconcileSymlinks(String home) {
    final claudeSkillsDir = Directory(p.join(home, '.claude', 'skills'));
    final agentsSkillsDir = Directory(p.join(home, '.agents', 'skills'));
    if (!claudeSkillsDir.existsSync() || !agentsSkillsDir.existsSync()) {
      return;
    }

    // A. Add missing relative links
    for (final entity in agentsSkillsDir.listSync()) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        final targetLink = Link(p.join(claudeSkillsDir.path, name));
        if (FileSystemEntity.typeSync(targetLink.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          targetLink.createSync('../../.agents/skills/$name', recursive: true);
        }
      }
    }

    // B. Prune dangling non-GC links
    for (final entity in claudeSkillsDir.listSync(followLinks: false)) {
      if (entity is Link) {
        final name = p.basename(entity.path);
        if (name.startsWith('core.gc-')) continue;

        // Check if link is dangling (target doesn't exist)
        final targetPath = entity.targetSync();
        final resolvedTarget = p.isAbsolute(targetPath)
            ? targetPath
            : p.normalize(p.join(claudeSkillsDir.path, targetPath));

        if (FileSystemEntity.typeSync(resolvedTarget) ==
            FileSystemEntityType.notFound) {
          entity.deleteSync();
        }
      }
    }
  }
}
