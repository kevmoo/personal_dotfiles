import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
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
      final dirty = await uncommittedSkillFiles(home);

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

        if (needsReconciliation(home)) {
          return UpkeepStatus(
            upkeeperId: id,
            displayName: displayName,
            state: UpkeepState.outdated,
            summary: 'Agent skills symlinks need reconciliation',
          );
        }

        if (dirty.isNotEmpty) {
          return UpkeepStatus(
            upkeeperId: id,
            displayName: displayName,
            state: UpkeepState.outdated,
            summary:
                'Agent skills have uncommitted changes in ~/.dotfiles (${dirty.length} file(s))',
            details: dirty,
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
          details: [output, ...dirty],
        );
      }

      if (needsReconciliation(home)) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Agent skills symlinks need reconciliation',
          details: dirty,
        );
      }

      if (dirty.isNotEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary:
              'Agent skills have uncommitted changes in ~/.dotfiles (${dirty.length} file(s))',
          details: dirty,
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

      // 3. Normalize .agents/.skill-lock.json (pin updatedAt -> installedAt)
      normalizeSkillLock(home);

      // 4. Reconcile symlinks in ~/.claude/skills/
      reconcileSymlinks(home);

      // 5. Report any uncommitted/untracked files under .agents in ~/.dotfiles
      final dirty = await uncommittedSkillFiles(home);
      final dirtySuffix = dirty.isNotEmpty
          ? ' (${dirty.length} uncommitted/untracked file(s) in ~/.agents/)'
          : '';

      if (globalSuccess && localSuccess) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message:
              'Successfully updated agent skills (global and local)$dirtySuffix',
        );
      } else {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to update some agent skills$dirtySuffix',
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

  /// Pins `updatedAt` to `installedAt` for every entry in
  /// `.agents/.skill-lock.json` so `npx skills` timestamp churn does not dirty
  /// `~/.dotfiles` across machines.
  @visibleForTesting
  void normalizeSkillLock(String home) {
    final lockFile = File(p.join(home, '.agents', '.skill-lock.json'));
    if (!lockFile.existsSync()) return;
    try {
      final raw = lockFile.readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final skills = decoded['skills'];
      if (skills is! Map<String, dynamic>) return;

      var changed = false;
      for (final entry in skills.values) {
        if (entry is Map<String, dynamic>) {
          final installedAt = entry['installedAt'];
          if (installedAt is String && entry['updatedAt'] != installedAt) {
            entry['updatedAt'] = installedAt;
            changed = true;
          }
        }
      }

      if (changed) {
        final normalized = const JsonEncoder.withIndent('  ').convert(decoded);
        if (normalized != raw) {
          lockFile.writeAsStringSync(normalized);
        }
      }
    } catch (_) {
      // Ignore malformed lockfile; leave untouched for git/user inspection.
    }
  }

  /// Returns modified or untracked files under `.agents` in `~/.dotfiles`
  /// using `git status --porcelain -u -- .agents`.
  @visibleForTesting
  Future<List<String>> uncommittedSkillFiles(String home) async {
    normalizeSkillLock(home);
    final gitDir = p.join(home, '.dotfiles');
    if (!Directory(gitDir).existsSync()) return const [];
    try {
      final proc = await Process.run('git', [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'status',
        '--porcelain',
        '-u',
        '--',
        '.agents',
      ], workingDirectory: home);
      if (proc.exitCode != 0) return const [];
      return proc.stdout
          .toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Whether any agent-integration target is missing skill links or holds
  /// dangling ones. Exposed for testing; drive with a temp home directory.
  @visibleForTesting
  bool needsReconciliation(String home) {
    final agentsSkillsDir = Directory(p.join(home, '.agents', 'skills'));
    if (!agentsSkillsDir.existsSync()) return false;
    return _claudeNeedsReconciliation(home, agentsSkillsDir) ||
        _geminiNeedsReconciliation(home, agentsSkillsDir);
  }

  /// Creates missing skill links and prunes dangling ones for every
  /// agent-integration target. Exposed for testing; drive with a temp home.
  @visibleForTesting
  void reconcileSymlinks(String home) {
    final agentsSkillsDir = Directory(p.join(home, '.agents', 'skills'));
    if (!agentsSkillsDir.existsSync()) return;

    // 1. Claude skills: relative links from ~/.claude/skills.
    final claudeSkillsDir = Directory(p.join(home, '.claude', 'skills'));
    if (claudeSkillsDir.existsSync()) {
      _createMissingLinks(
        agentsSkillsDir,
        claudeSkillsDir,
        (name, _) => '../../.agents/skills/$name',
      );
      _pruneDanglingLinks(claudeSkillsDir, skipPrefix: 'core.gc-');
    }

    final geminiDir = Directory(p.join(home, '.gemini'));
    if (!geminiDir.existsSync()) return;

    // 2. Global user-plugin skills: absolute links.
    final userPluginSkillsDir = Directory(
      p.join(geminiDir.path, 'config', 'plugins', 'user-plugin', 'skills'),
    );
    if (userPluginSkillsDir.existsSync()) {
      _createMissingLinks(
        agentsSkillsDir,
        userPluginSkillsDir,
        (_, skillDir) => skillDir.path,
      );
      _pruneDanglingLinks(userPluginSkillsDir);
    }

    // 3. Antigravity IDE links into the user plugin.
    final ideDir = Directory(p.join(geminiDir.path, 'antigravity-ide'));
    final configUserPlugin = Directory(
      p.join(geminiDir.path, 'config', 'plugins', 'user-plugin'),
    );
    if (ideDir.existsSync() && configUserPlugin.existsSync()) {
      _ensureLink(
        p.join(ideDir.path, 'skills'),
        p.join(configUserPlugin.path, 'skills'),
      );
      Directory(p.join(ideDir.path, 'plugins')).createSync(recursive: true);
      _ensureLink(
        p.join(ideDir.path, 'plugins', 'user-plugin'),
        configUserPlugin.path,
      );
    }
  }
}

/// Whether the `.claude/skills` target is missing links or holds dangling
/// non-GC-managed ones.
bool _claudeNeedsReconciliation(String home, Directory agentsSkillsDir) {
  final claudeSkillsDir = Directory(p.join(home, '.claude', 'skills'));
  if (!claudeSkillsDir.existsSync()) return false;
  return _hasMissingLinks(agentsSkillsDir, claudeSkillsDir) ||
      _hasDanglingLinks(claudeSkillsDir, skipPrefix: 'core.gc-');
}

/// Whether any `.gemini` target (user-plugin skills, antigravity IDE) is
/// missing links or holds dangling ones.
bool _geminiNeedsReconciliation(String home, Directory agentsSkillsDir) {
  final geminiDir = Directory(p.join(home, '.gemini'));
  if (!geminiDir.existsSync()) return false;

  final userPluginSkillsDir = Directory(
    p.join(geminiDir.path, 'config', 'plugins', 'user-plugin', 'skills'),
  );
  if (userPluginSkillsDir.existsSync() &&
      (_hasMissingLinks(agentsSkillsDir, userPluginSkillsDir) ||
          _hasDanglingLinks(userPluginSkillsDir))) {
    return true;
  }

  final ideDir = Directory(p.join(geminiDir.path, 'antigravity-ide'));
  final configUserPlugin = Directory(
    p.join(geminiDir.path, 'config', 'plugins', 'user-plugin'),
  );
  return ideDir.existsSync() &&
      configUserPlugin.existsSync() &&
      (_linkMissing(p.join(ideDir.path, 'skills')) ||
          _linkMissing(p.join(ideDir.path, 'plugins', 'user-plugin')));
}

/// Skill directories under `.agents/skills`.
Iterable<Directory> _skillDirs(Directory agentsSkillsDir) =>
    agentsSkillsDir.listSync().whereType<Directory>();

/// Whether no filesystem entity (following nothing) exists at [linkPath].
bool _linkMissing(String linkPath) =>
    FileSystemEntity.typeSync(linkPath, followLinks: false) ==
    FileSystemEntityType.notFound;

/// Whether any skill dir in [agentsSkillsDir] lacks a link in [targetDir].
bool _hasMissingLinks(Directory agentsSkillsDir, Directory targetDir) =>
    _skillDirs(agentsSkillsDir).any(
      (skillDir) =>
          _linkMissing(p.join(targetDir.path, p.basename(skillDir.path))),
    );

/// Links in [dir] whose resolved target no longer exists, skipping names
/// starting with [skipPrefix].
Iterable<Link> _danglingLinks(Directory dir, {String? skipPrefix}) sync* {
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! Link) continue;
    if (skipPrefix != null && p.basename(entity.path).startsWith(skipPrefix)) {
      continue;
    }
    final targetPath = entity.targetSync();
    final resolvedTarget = p.isAbsolute(targetPath)
        ? targetPath
        : p.normalize(p.join(dir.path, targetPath));
    if (FileSystemEntity.typeSync(resolvedTarget) ==
        FileSystemEntityType.notFound) {
      yield entity;
    }
  }
}

bool _hasDanglingLinks(Directory dir, {String? skipPrefix}) =>
    _danglingLinks(dir, skipPrefix: skipPrefix).isNotEmpty;

/// Creates a link for each skill dir missing in [targetDir]; [linkTarget]
/// computes the link destination from the skill name and directory.
void _createMissingLinks(
  Directory agentsSkillsDir,
  Directory targetDir,
  String Function(String name, Directory skillDir) linkTarget,
) {
  for (final skillDir in _skillDirs(agentsSkillsDir)) {
    final name = p.basename(skillDir.path);
    final link = Link(p.join(targetDir.path, name));
    if (_linkMissing(link.path)) {
      link.createSync(linkTarget(name, skillDir), recursive: true);
    }
  }
}

void _pruneDanglingLinks(Directory dir, {String? skipPrefix}) {
  for (final link in _danglingLinks(dir, skipPrefix: skipPrefix).toList()) {
    link.deleteSync();
  }
}

/// Creates [linkPath] pointing at [target] unless something already exists.
void _ensureLink(String linkPath, String target) {
  if (_linkMissing(linkPath)) {
    Link(linkPath).createSync(target, recursive: true);
  }
}
