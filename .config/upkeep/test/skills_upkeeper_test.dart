import 'dart:io';

import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('SkillsUpkeeper', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('skills_upkeep_test_');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('isSupported is false when no skills setup exists', () async {
      final upkeeper = SkillsUpkeeper(homeDirOverride: tempHome.path);

      check(await upkeeper.isSupported()).isFalse();
    });
  });

  group('SkillsUpkeeper symlink reconciliation', () {
    late Directory tempHome;
    late String home;
    late SkillsUpkeeper upkeeper;

    String path(List<String> segments) => p.joinAll([home, ...segments]);

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('skills_links_test_');
      home = tempHome.path;
      upkeeper = SkillsUpkeeper(homeDirOverride: home);

      // Source of truth: two skills under .agents/skills.
      Directory(path(['.agents', 'skills', 'alpha']))
          .createSync(recursive: true);
      Directory(path(['.agents', 'skills', 'beta']))
          .createSync(recursive: true);
    });

    tearDown(() async {
      await tempHome.delete(recursive: true);
    });

    test('no-op when .agents/skills is absent', () {
      final bare = Directory(p.join(home, 'other'))..createSync();
      check(upkeeper.needsReconciliation(bare.path)).isFalse();
      upkeeper.reconcileSymlinks(bare.path); // must not throw
    });

    test('clean home with no integration targets needs nothing', () {
      check(upkeeper.needsReconciliation(home)).isFalse();
    });

    test('creates missing relative links for claude skills', () {
      Directory(path(['.claude', 'skills'])).createSync(recursive: true);

      check(upkeeper.needsReconciliation(home)).isTrue();
      upkeeper.reconcileSymlinks(home);
      check(upkeeper.needsReconciliation(home)).isFalse();

      final link = Link(path(['.claude', 'skills', 'alpha']));
      check(link.existsSync()).isTrue();
      check(link.targetSync()).equals('../../.agents/skills/alpha');
      check(Link(path(['.claude', 'skills', 'beta'])).existsSync()).isTrue();
    });

    test('prunes dangling claude links but preserves core.gc- links', () {
      Directory(path(['.claude', 'skills'])).createSync(recursive: true);
      Link(path(['.claude', 'skills', 'dead']))
          .createSync('../../.agents/skills/gone');
      Link(path(['.claude', 'skills', 'core.gc-managed']))
          .createSync('../../.agents/skills/also-gone');

      check(upkeeper.needsReconciliation(home)).isTrue();
      upkeeper.reconcileSymlinks(home);
      check(upkeeper.needsReconciliation(home)).isFalse();

      check(
        FileSystemEntity.typeSync(
          path(['.claude', 'skills', 'dead']),
          followLinks: false,
        ),
      ).equals(FileSystemEntityType.notFound);
      // GC-managed links are never pruned and never trigger reconciliation.
      check(
        FileSystemEntity.typeSync(
          path(['.claude', 'skills', 'core.gc-managed']),
          followLinks: false,
        ),
      ).equals(FileSystemEntityType.link);
    });

    test('creates absolute links and IDE links for gemini targets', () {
      Directory(path(['.gemini', 'config', 'plugins', 'user-plugin', 'skills']))
          .createSync(recursive: true);
      Directory(path(['.gemini', 'antigravity-ide']))
          .createSync(recursive: true);

      check(upkeeper.needsReconciliation(home)).isTrue();
      upkeeper.reconcileSymlinks(home);
      check(upkeeper.needsReconciliation(home)).isFalse();

      final skillLink = Link(
        path([
          '.gemini',
          'config',
          'plugins',
          'user-plugin',
          'skills',
          'alpha',
        ]),
      );
      check(skillLink.existsSync()).isTrue();
      check(skillLink.targetSync())
          .equals(path(['.agents', 'skills', 'alpha']));

      check(
        Link(path(['.gemini', 'antigravity-ide', 'skills'])).targetSync(),
      ).equals(path(['.gemini', 'config', 'plugins', 'user-plugin', 'skills']));
      check(
        Link(path(['.gemini', 'antigravity-ide', 'plugins', 'user-plugin']))
            .targetSync(),
      ).equals(path(['.gemini', 'config', 'plugins', 'user-plugin']));
    });

    test('reconciliation is idempotent', () {
      Directory(path(['.claude', 'skills'])).createSync(recursive: true);
      Directory(path(['.gemini', 'config', 'plugins', 'user-plugin', 'skills']))
          .createSync(recursive: true);

      upkeeper.reconcileSymlinks(home);
      upkeeper.reconcileSymlinks(home); // second run must not throw
      check(upkeeper.needsReconciliation(home)).isFalse();
    });
  });
}
