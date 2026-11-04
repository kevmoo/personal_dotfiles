import 'dart:io';

import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('DotfilesUpkeeper.update', () {
    late Directory temp;
    late String home;
    late String publisher;

    Future<String> git(String dir, List<String> args) async {
      final result = await Process.run('git', [
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
      check(result.exitCode, because: '${result.stderr}').equals(0);
      return result.stdout.toString().trim();
    }

    Future<void> publish(String content) async {
      File(p.join(publisher, 'config')).writeAsStringSync(content);
      await git(publisher, ['add', 'config']);
      await git(publisher, ['commit', '-m', content]);
      await git(publisher, ['push', 'origin', 'main']);
    }

    String readConfig() => File(p.join(home, 'config')).readAsStringSync();

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('dotfiles_update_test_');
      final origin = p.join(temp.path, 'origin.git');
      publisher = p.join(temp.path, 'publisher');
      home = p.join(temp.path, 'home');

      Directory(home).createSync();
      await git(temp.path, ['init', '--bare', origin]);
      await git(temp.path, ['init', publisher]);
      await git(publisher, ['remote', 'add', 'origin', origin]);
      await publish('v1');
      await git(temp.path, [
        'clone',
        '--branch',
        'main',
        '--separate-git-dir=${p.join(home, '.dotfiles')}',
        origin,
        p.join(temp.path, 'seed'),
      ]);
      File(p.join(home, 'config')).writeAsStringSync('v1');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('pulls past local changes that already match upstream', () async {
      await publish('v2');
      File(p.join(home, 'config')).writeAsStringSync('v2');

      final result = await DotfilesUpkeeper(homeDirOverride: home).update();

      check(result.success).isTrue();
      check(readConfig()).equals('v2');
      final gitDir = p.join(home, '.dotfiles');
      final status = await git(home, [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'status',
        '--porcelain',
        '--untracked-files=no',
      ]);
      final stashes = await git(home, [
        '--git-dir=$gitDir',
        '--work-tree=$home',
        'stash',
        'list',
      ]);
      check(status).isEmpty();
      check(stashes).isEmpty();
    });

    test('refuses to pull over different local changes', () async {
      await publish('v2');
      File(p.join(home, 'config')).writeAsStringSync('local edit');

      final result = await DotfilesUpkeeper(homeDirOverride: home).update();

      check(result.success).isFalse();
      check(readConfig()).equals('local edit');
    });

    test(
      'pulls normally with a clean tree and reconciles skill symlinks',
      () async {
        Directory(p.join(home, '.agents', 'skills', 'alpha'))
            .createSync(recursive: true);
        Directory(p.join(home, '.claude', 'skills'))
            .createSync(recursive: true);
        await publish('v2');

        final result = await DotfilesUpkeeper(homeDirOverride: home).update();

        check(result.success).isTrue();
        check(readConfig()).equals('v2');
        check(Link(p.join(home, '.claude', 'skills', 'alpha')).existsSync())
            .isTrue();
      },
    );

    test('fast-forwards unrelated upstream changes when another tracked file is dirty', () async {
      File(p.join(publisher, 'skills_doc')).writeAsStringSync('s1');
      await git(publisher, ['add', 'skills_doc']);
      await git(publisher, ['commit', '-m', 'add skills_doc']);
      await git(publisher, ['push', 'origin', 'main']);
      await DotfilesUpkeeper(homeDirOverride: home).update();

      // Simulate dirty `.agents/` file on disk while upstream advances `config`.
      File(p.join(home, 'skills_doc')).writeAsStringSync('local skill sync');
      await publish('v2');

      final result = await DotfilesUpkeeper(homeDirOverride: home).update();

      check(result.success).isTrue();
      check(readConfig()).equals('v2');
      check(File(p.join(home, 'skills_doc')).readAsStringSync())
          .equals('local skill sync');
    });
  });
}
