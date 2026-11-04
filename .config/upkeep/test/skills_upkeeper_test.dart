import 'dart:convert';
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

  group('SkillsUpkeeper.staleSkills', () {
    late Directory tempHome;
    late String home;
    late List<List<String>> calls;

    void writeLock(Map<String, Object> skills) {
      File(p.join(home, '.agents', '.skill-lock.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'version': 3, 'skills': skills}));
    }

    Map<String, Object> entry(
      String source,
      String hash, {
      String sourceType = 'github',
    }) => {
      'source': source,
      'sourceType': sourceType,
      'skillPath': 'skills/alpha/SKILL.md',
      'skillFolderHash': hash,
    };

    SkillsUpkeeper upkeeperWith(ProcessResult Function(String source) reply) =>
        SkillsUpkeeper(
          homeDirOverride: home,
          processRunner: (executable, arguments) async {
            calls.add([executable, ...arguments]);
            return reply(arguments[1].split('/').sublist(1, 3).join('/'));
          },
        );

    ProcessResult tree(Map<String, String> folders, {bool truncated = false}) =>
        ProcessResult(
          0,
          0,
          jsonEncode({
            'truncated': truncated,
            'tree': [
              for (final MapEntry(key: path, value: sha) in folders.entries)
                {'path': path, 'type': 'tree', 'sha': sha},
              {'path': 'README.md', 'type': 'blob', 'sha': 'blob'},
            ],
          }),
          '',
        );

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('skills_stale_test_');
      home = tempHome.path;
      calls = [];
    });

    tearDown(() async {
      await tempHome.delete(recursive: true);
    });

    test(
      'reports a skill whose hash differs from the source tree as needsTriage',
      () async {
        writeLock({'alpha': entry('kevmoo/repo', 'old')});
        final upkeeper = upkeeperWith((_) => tree({'skills/alpha': 'new'}));

        final status = await upkeeper.check();

        check(status.state).equals(UpkeepState.needsTriage);
        check(status.actionHint).equals('upkeep update skills');
        check(status.details.single)
            .equals('alpha: update available from kevmoo/repo');
      },
    );

    test('reports outdated when symlinks need reconciliation even if upstream is ahead', () async {
      writeLock({'alpha': entry('kevmoo/repo', 'old')});
      Directory(p.join(home, '.agents', 'skills', 'alpha'))
          .createSync(recursive: true);
      Directory(p.join(home, '.claude', 'skills')).createSync(recursive: true);
      final upkeeper = upkeeperWith((_) => tree({'skills/alpha': 'new'}));

      final status = await upkeeper.check();

      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).equals('Agent skills symlinks need reconciliation');
      check(status.details)
          .contains('alpha: update available from kevmoo/repo');
    });

    test('routine update reconciles symlinks without invoking npx', () async {
      Directory(p.join(home, '.agents', 'skills', 'alpha'))
          .createSync(recursive: true);
      Directory(p.join(home, '.claude', 'skills')).createSync(recursive: true);
      final upkeeper = SkillsUpkeeper(
        homeDirOverride: home,
        processRunner: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update();

      check(result.success).isTrue();
      check(calls).isEmpty();
      check(Link(p.join(home, '.claude', 'skills', 'alpha')).existsSync())
          .isTrue();
    });

    test('explicit syncUpstream update invokes npx skills update', () async {
      Directory(p.join(home, '.agents', 'skills', 'alpha'))
          .createSync(recursive: true);
      Directory(p.join(home, '.claude', 'skills')).createSync(recursive: true);
      final upkeeper = SkillsUpkeeper(
        homeDirOverride: home,
        processRunner: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update(syncUpstream: true);

      check(result.success).isTrue();
      check(calls).deepEquals([
        ['npx', 'skills', 'update', '-g'],
        ['npx', 'skills', 'update'],
      ]);
      check(Link(p.join(home, '.claude', 'skills', 'alpha')).existsSync())
          .isTrue();
    });

    test('never invokes npx, because skills check applies updates', () async {
      writeLock({'alpha': entry('kevmoo/repo', 'same')});
      final upkeeper = upkeeperWith((_) => tree({'skills/alpha': 'same'}));

      final status = await upkeeper.check();

      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).equals('Agent skills up to date');
      check(calls.single.first).equals('gh');
    });

    test('fetches each source once', () async {
      writeLock({
        'alpha': entry('kevmoo/repo', 'same'),
        'beta': entry('kevmoo/repo', 'same'),
      });
      final upkeeper = upkeeperWith((_) => tree({'skills/alpha': 'same'}));

      check(await upkeeper.staleSkills(home)).isNotNull().isEmpty();
      check(calls).length.equals(1);
    });

    test('reports a skill missing from its source', () async {
      writeLock({'alpha': entry('kevmoo/repo', 'same')});
      final upkeeper = upkeeperWith((_) => tree({}));

      check(await upkeeper.staleSkills(home))
          .isNotNull()
          .deepEquals(['alpha: missing from kevmoo/repo at skills/alpha']);
    });

    test('ignores non-GitHub sources', () async {
      writeLock({'alpha': entry('local', 'x', sourceType: 'local')});
      final upkeeper = upkeeperWith((_) => tree({}));

      check(await upkeeper.staleSkills(home)).isNotNull().isEmpty();
      check(calls).isEmpty();
    });

    test('skips the check when gh fails', () async {
      writeLock({'alpha': entry('kevmoo/repo', 'same')});
      final upkeeper = upkeeperWith((_) => ProcessResult(0, 1, '', 'nope'));

      final status = await upkeeper.check();

      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).equals('Agent skills present (check skipped)');
    });

    test('skips the check when the tree is truncated', () async {
      writeLock({'alpha': entry('kevmoo/repo', 'same')});
      final upkeeper = upkeeperWith(
        (_) => tree({'skills/alpha': 'same'}, truncated: true),
      );

      check(await upkeeper.staleSkills(home)).isNull();
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

    test('uncommittedSkillFiles detects untracked files even when status.showUntrackedFiles is no', () async {
      final dotfilesBare = Directory(path(['.dotfiles']));
      await Process.run('git', ['init', '--bare', dotfilesBare.path]);
      await Process.run('git', [
        '--git-dir=${dotfilesBare.path}',
        '--work-tree=$home',
        'config',
        'status.showUntrackedFiles',
        'no',
      ]);
      File(p.join(dotfilesBare.path, 'info', 'exclude')).writeAsStringSync(
        '*\n!.agents/\n!.agents/skills/\n!.agents/skills/**\n',
      );

      final evalFile =
          File(path(['.agents', 'skills', 'alpha', 'evals', 'evals.json']))
            ..createSync(recursive: true)
            ..writeAsStringSync('{}');

      final dirty = await upkeeper.uncommittedSkillFiles(home);
      check(dirty).isNotEmpty();
      check(dirty.single).contains('evals/evals.json');

      final dotfilesUpkeeper = DotfilesUpkeeper(homeDirOverride: home);
      final status = await dotfilesUpkeeper.check();
      check(status.state).equals(UpkeepState.needsTriage);
      check(status.actionHint).equals('dot status');
      check(status.summary).contains('uncommitted/untracked file(s)');

      evalFile.deleteSync();
    });

    test(
      'normalizeSkillLock pins updatedAt to installedAt in .skill-lock.json',
      () async {
        final dotfilesBare = Directory(path(['.dotfiles']));
        await Process.run('git', ['init', '--bare', dotfilesBare.path]);
        File(p.join(dotfilesBare.path, 'info', 'exclude'))
            .writeAsStringSync('*\n!.agents/\n!.agents/.skill-lock.json\n');

        final lockFile = File(path(['.agents', '.skill-lock.json']))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            '{\n'
            '  "version": 3,\n'
            '  "skills": {\n'
            '    "alpha": {\n'
            '      "installedAt": "2026-06-05T01:21:48.061Z",\n'
            '      "updatedAt": "2026-06-05T01:21:48.061Z"\n'
            '    }\n'
            '  }\n'
            '}',
          );

        await Process.run('git', [
          '--git-dir=${dotfilesBare.path}',
          '--work-tree=$home',
          'add',
          '.agents/.skill-lock.json',
        ]);
        await Process.run('git', [
          '--git-dir=${dotfilesBare.path}',
          '--work-tree=$home',
          'commit',
          '-m',
          'initial lock',
        ]);

        // Simulate `npx skills update` bumping only updatedAt.
        lockFile.writeAsStringSync(
          '{\n'
          '  "version": 3,\n'
          '  "skills": {\n'
          '    "alpha": {\n'
          '      "installedAt": "2026-06-05T01:21:48.061Z",\n'
          '      "updatedAt": "2026-09-23T18:00:00.000Z"\n'
          '    }\n'
          '  }\n'
          '}',
        );

        upkeeper.normalizeSkillLock(home);

        final dirty = await upkeeper.uncommittedSkillFiles(home);
        check(dirty).isEmpty();
        check(lockFile.readAsStringSync())
            .contains('"updatedAt": "2026-06-05T01:21:48.061Z"');
        check(lockFile.readAsStringSync().endsWith('\n')).isFalse();
      },
    );
  });
}
