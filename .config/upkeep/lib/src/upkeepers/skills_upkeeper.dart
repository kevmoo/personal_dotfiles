import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class SkillsUpkeeper implements Upkeeper {
  final String? homeDirOverride;

  SkillsUpkeeper({this.homeDirOverride});

  @override
  String get id => 'skills';

  @override
  String get displayName => 'Agent Skills';

  @override
  Future<bool> isSupported() async {
    try {
      final home = _homeDir();
      final configured =
          Directory(p.join(home, '.agents', 'skills')).existsSync() ||
          File(p.join(home, '.agents', '.skill-lock.json')).existsSync();
      if (!configured) return false;
      final result = await Process.run('which', ['npx']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _homeDir() =>
      homeDirOverride ?? Platform.environment['HOME'] ?? Directory.current.path;

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
    final agentsSkillsDir = Directory(p.join(home, '.agents', 'skills'));
    if (!agentsSkillsDir.existsSync()) {
      return false;
    }

    // 1. Claude skills check
    final claudeSkillsDir = Directory(p.join(home, '.claude', 'skills'));
    if (claudeSkillsDir.existsSync()) {
      // Check for missing relative links
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

      // Check for dangling non-GC links
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
    }

    final geminiDir = Directory(p.join(home, '.gemini'));
    if (geminiDir.existsSync()) {
      // 2. Global user-plugin skills directory check
      final userPluginSkillsDir = Directory(
        p.join(geminiDir.path, 'config', 'plugins', 'user-plugin', 'skills'),
      );
      if (userPluginSkillsDir.existsSync()) {
        // Check for missing relative links
        for (final entity in agentsSkillsDir.listSync()) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            final targetLink = Link(p.join(userPluginSkillsDir.path, name));
            if (FileSystemEntity.typeSync(
                  targetLink.path,
                  followLinks: false,
                ) ==
                FileSystemEntityType.notFound) {
              return true;
            }
          }
        }

        // Check for dangling links
        for (final entity in userPluginSkillsDir.listSync(followLinks: false)) {
          if (entity is Link) {
            final targetPath = entity.targetSync();
            final resolvedTarget = p.isAbsolute(targetPath)
                ? targetPath
                : p.normalize(p.join(userPluginSkillsDir.path, targetPath));

            if (FileSystemEntity.typeSync(resolvedTarget) ==
                FileSystemEntityType.notFound) {
              return true;
            }
          }
        }
      }

      // 3. Antigravity IDE check
      final ideDir = Directory(p.join(geminiDir.path, 'antigravity-ide'));
      if (ideDir.existsSync()) {
        final configUserPlugin = Directory(
          p.join(geminiDir.path, 'config', 'plugins', 'user-plugin'),
        );
        if (configUserPlugin.existsSync()) {
          // Check ~/.gemini/antigravity-ide/skills
          final ideSkillsLink = Link(p.join(ideDir.path, 'skills'));
          if (FileSystemEntity.typeSync(
                ideSkillsLink.path,
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
            return true;
          }

          // Check ~/.gemini/antigravity-ide/plugins/user-plugin
          final ideUserPluginLink = Link(
            p.join(ideDir.path, 'plugins', 'user-plugin'),
          );
          if (FileSystemEntity.typeSync(
                ideUserPluginLink.path,
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
            return true;
          }
        }
      }
    }

    return false;
  }

  void _reconcileSymlinks(String home) {
    final agentsSkillsDir = Directory(p.join(home, '.agents', 'skills'));
    if (!agentsSkillsDir.existsSync()) {
      return;
    }

    // 1. Claude skills reconciliation
    final claudeSkillsDir = Directory(p.join(home, '.claude', 'skills'));
    if (claudeSkillsDir.existsSync()) {
      // Add missing relative links
      for (final entity in agentsSkillsDir.listSync()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          final targetLink = Link(p.join(claudeSkillsDir.path, name));
          if (FileSystemEntity.typeSync(targetLink.path, followLinks: false) ==
              FileSystemEntityType.notFound) {
            targetLink.createSync(
              '../../.agents/skills/$name',
              recursive: true,
            );
          }
        }
      }

      // Prune dangling non-GC links
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

    final geminiDir = Directory(p.join(home, '.gemini'));
    if (geminiDir.existsSync()) {
      // 2. Global user-plugin skills directory reconciliation
      final userPluginSkillsDir = Directory(
        p.join(geminiDir.path, 'config', 'plugins', 'user-plugin', 'skills'),
      );
      if (userPluginSkillsDir.existsSync()) {
        for (final entity in agentsSkillsDir.listSync()) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            final targetLink = Link(p.join(userPluginSkillsDir.path, name));
            if (FileSystemEntity.typeSync(
                  targetLink.path,
                  followLinks: false,
                ) ==
                FileSystemEntityType.notFound) {
              targetLink.createSync(entity.path);
            }
          }
        }
        for (final entity in userPluginSkillsDir.listSync(followLinks: false)) {
          if (entity is Link) {
            final targetPath = entity.targetSync();
            final resolvedTarget = p.isAbsolute(targetPath)
                ? targetPath
                : p.normalize(p.join(userPluginSkillsDir.path, targetPath));

            if (FileSystemEntity.typeSync(resolvedTarget) ==
                FileSystemEntityType.notFound) {
              entity.deleteSync();
            }
          }
        }
      }

      // 3. Antigravity IDE skills & plugin links reconciliation
      final ideDir = Directory(p.join(geminiDir.path, 'antigravity-ide'));
      if (ideDir.existsSync()) {
        final configUserPlugin = Directory(
          p.join(geminiDir.path, 'config', 'plugins', 'user-plugin'),
        );
        if (configUserPlugin.existsSync()) {
          // Reconcile ~/.gemini/antigravity-ide/skills -> ~/.gemini/config/plugins/user-plugin/skills
          final ideSkillsLink = Link(p.join(ideDir.path, 'skills'));
          final targetSkillsDir = p.join(configUserPlugin.path, 'skills');
          if (FileSystemEntity.typeSync(
                ideSkillsLink.path,
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
            ideSkillsLink.createSync(targetSkillsDir, recursive: true);
          }

          // Reconcile ~/.gemini/antigravity-ide/plugins/user-plugin -> ~/.gemini/config/plugins/user-plugin
          final idePluginsDir = Directory(p.join(ideDir.path, 'plugins'));
          if (!idePluginsDir.existsSync()) {
            idePluginsDir.createSync();
          }
          final ideUserPluginLink = Link(
            p.join(idePluginsDir.path, 'user-plugin'),
          );
          if (FileSystemEntity.typeSync(
                ideUserPluginLink.path,
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
            ideUserPluginLink.createSync(configUserPlugin.path);
          }
        }
      }
    }
  }
}
