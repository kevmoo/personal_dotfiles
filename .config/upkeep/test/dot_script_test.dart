import 'dart:io';

import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('~/.local/bin/dot wrapper', () {
    late Directory temp;
    late String home;
    late String publisher;
    final dotScript = p.normalize(
      p.join(Directory.current.path, '..', '..', '.local', 'bin', 'dot'),
    );

    Future<ProcessResult> runGit(String dir, List<String> args) =>
        Process.run('git', [
          '-c',
          'user.name=test',
          '-c',
          'user.email=test@example.com',
          '-c',
          'core.hooksPath=/dev/null',
          '-c',
          'init.defaultBranch=main',
          ...args,
        ], workingDirectory: dir);

    Future<String> gitOk(String dir, List<String> args) async {
      final res = await runGit(dir, args);
      check(res.exitCode, because: '${res.stderr}').equals(0);
      return res.stdout.toString().trim();
    }

    Future<ProcessResult> runDot(List<String> args) => Process.run(
      dotScript,
      args,
      workingDirectory: home,
      environment: {...Platform.environment, 'HOME': home},
    );

    Future<void> publishFile(String relPath, String content) async {
      final file = File(p.join(publisher, relPath))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
      await gitOk(publisher, ['add', file.path]);
      await gitOk(publisher, ['commit', '-m', 'update $relPath']);
      await gitOk(publisher, ['push', 'origin', 'main']);
    }

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('dot_script_test_');
      final origin = p.join(temp.path, 'origin.git');
      publisher = p.join(temp.path, 'publisher');
      home = p.join(temp.path, 'home');

      Directory(home).createSync();
      await gitOk(temp.path, ['init', '--bare', origin]);
      await gitOk(temp.path, ['init', publisher]);
      await gitOk(publisher, ['remote', 'add', 'origin', origin]);
      await publishFile('config', 'v1');
      await publishFile('.agents/skills/alpha/SKILL.md', 'alpha v1');
      await gitOk(temp.path, [
        'clone',
        '--branch',
        'main',
        '--separate-git-dir=${p.join(home, '.dotfiles')}',
        origin,
        p.join(temp.path, 'seed'),
      ]);
      File(p.join(home, 'config')).writeAsStringSync('v1');
      File(p.join(home, '.agents', 'skills', 'alpha', 'SKILL.md'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('alpha v1');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('fast-paths non-pull commands including leading git flags', () async {
      final res = await runDot(['-c', 'color.ui=never', 'status', '-s']);

      check(res.exitCode, because: '${res.stderr}').equals(0);
    });

    test(
      'dot pull and dot pull --ff-only absorb local changes matching upstream',
      () async {
        await publishFile('.agents/skills/alpha/SKILL.md', 'alpha v2');
        File(p.join(home, '.agents', 'skills', 'alpha', 'SKILL.md'))
            .writeAsStringSync('alpha v2');

        final pull1 = await runDot(['pull']);
        check(pull1.exitCode, because: '${pull1.stderr}').equals(0);

        await publishFile('.agents/skills/alpha/SKILL.md', 'alpha v3');
        File(p.join(home, '.agents', 'skills', 'alpha', 'SKILL.md'))
            .writeAsStringSync('alpha v3');

        final pull2 = await runDot(['pull', '--ff-only']);
        check(pull2.exitCode, because: '${pull2.stderr}').equals(0);

        final status = await runDot(['status', '--porcelain', '-uno']);
        check(status.stdout.toString().trim()).isEmpty();
      },
    );

    test('dot pull fast-forwards unrelated changes while skills are dirty and reconciles symlinks', () async {
      Directory(p.join(home, '.claude', 'skills')).createSync(recursive: true);
      Link(p.join(home, '.claude', 'skills', 'stale'))
          .createSync('../../.agents/skills/gone');
      Link(p.join(home, '.claude', 'skills', 'core.gc-keep'))
          .createSync('../../.agents/skills/also-gone');

      File(p.join(home, '.agents', 'skills', 'alpha', 'SKILL.md'))
          .writeAsStringSync('local un-vendored edit');
      await publishFile('config', 'v2');
      await publishFile('.agents/skills/beta/SKILL.md', 'beta v1');

      final pullRes = await runDot(['pull']);
      check(pullRes.exitCode, because: '${pullRes.stderr}').equals(0);

      check(File(p.join(home, 'config')).readAsStringSync()).equals('v2');
      check(
        File(p.join(home, '.agents', 'skills', 'alpha', 'SKILL.md'))
            .readAsStringSync(),
      ).equals('local un-vendored edit');
      check(Link(p.join(home, '.claude', 'skills', 'alpha')).existsSync())
          .isTrue();
      check(Link(p.join(home, '.claude', 'skills', 'beta')).existsSync())
          .isTrue();
      check(
        FileSystemEntity.typeSync(
          p.join(home, '.claude', 'skills', 'stale'),
          followLinks: false,
        ),
      ).equals(FileSystemEntityType.notFound);
      check(
        FileSystemEntity.typeSync(
          p.join(home, '.claude', 'skills', 'core.gc-keep'),
          followLinks: false,
        ),
      ).equals(FileSystemEntityType.link);
    });

    test('dot pull refuses conflicting local edits', () async {
      await publishFile('config', 'upstream v2');
      File(p.join(home, 'config')).writeAsStringSync('conflicting local edit');

      final pullRes = await runDot(['pull']);
      check(pullRes.exitCode).not((it) => it.equals(0));
      check(File(p.join(home, 'config')).readAsStringSync())
          .equals('conflicting local edit');
    });
  });
}
