import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('LocalBinUpkeeper', () {
    late Directory tempHome;
    late Directory binDir;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('local_bin_test_');
      binDir = Directory('${tempHome.path}/.local/bin')
        ..createSync(recursive: true);
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('isSupported is true when ~/.local/bin exists', () async {
      final upkeeper = LocalBinUpkeeper(homeDirOverride: () => tempHome.path);
      check(await upkeeper.isSupported()).isTrue;
    });

    test('isSupported is false when ~/.local/bin is absent', () async {
      binDir.deleteSync(recursive: true);
      final upkeeper = LocalBinUpkeeper(homeDirOverride: () => tempHome.path);
      check(await upkeeper.isSupported()).isFalse;
    });

    test(
      'check is upToDate when all entries are tracked or allowlisted',
      () async {
        Directory('${tempHome.path}/.dotfiles').createSync();
        Directory('${tempHome.path}/.dotfiles-corp').createSync();
        File('${binDir.path}/gh').writeAsStringSync('#!/bin/sh\n');
        File('${binDir.path}/dart').writeAsStringSync('#!/bin/sh\n');
        File('${binDir.path}/mise').writeAsStringSync('#!/bin/sh\n');
        File('${binDir.path}/LICENSE.txt').writeAsStringSync('MIT\n');

        File('${tempHome.path}/.config/upkeep/local_bin_allowlist')
          ..createSync(recursive: true)
          ..writeAsStringSync('# comment\nmise\n');

        final upkeeper = LocalBinUpkeeper(
          homeDirOverride: () => tempHome.path,
          processRunner: (executable, args) async {
            if (args.contains('--git-dir=${tempHome.path}/.dotfiles')) {
              return ProcessResult(0, 0, '.local/bin/gh\n', '');
            }
            if (args.contains('--git-dir=${tempHome.path}/.dotfiles-corp')) {
              return ProcessResult(0, 0, '.local/bin/dart\n', '');
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        final status = await upkeeper.check();
        check(status.state).equals(UpkeepState.upToDate);
        check(status.summary).contains('All 3 entries');
      },
    );

    test('check flags untracked files and broken symlinks', () async {
      File('${binDir.path}/mystery-script').writeAsStringSync('#!/bin/sh\n');
      Link('${binDir.path}/broken-link')
          .createSync('${tempHome.path}/does_not_exist');

      final upkeeper = LocalBinUpkeeper(
        homeDirOverride: () => tempHome.path,
        processRunner: (_, _) async => ProcessResult(0, 0, '', ''),
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.needsTriage);
      check(status.actionHint).isNotNull().contains('dot add -f');
      check(status.summary).contains('1 untracked, 1 broken symlink(s)');
      check(status.details).any(.it()..contains('mystery-script'));
      check(status.details).any(
        .it()
          ..contains('broken-link')
          ..contains('broken symlink'),
      );

      final updateRes = await upkeeper.update();
      check(updateRes.success).isFalse;
      check(updateRes.message).contains('Manual triage required');
    });

    test('check reports outdated for stale agy.*.old backups and update deletes them', () async {
      File('${binDir.path}/agy').writeAsStringSync('#!/bin/sh\n');
      final stale1 = File('${binDir.path}/agy.1795302543087764083.old')
        ..writeAsStringSync('old binary 1');
      final stale2 = File('${binDir.path}/agy.12345.old')
        ..writeAsStringSync('old binary 2');

      File('${tempHome.path}/.config/upkeep/local_bin_allowlist')
        ..createSync(recursive: true)
        ..writeAsStringSync('agy\n');

      final upkeeper = LocalBinUpkeeper(
        homeDirOverride: () => tempHome.path,
        processRunner: (_, _) async => ProcessResult(0, 0, '', ''),
      );

      final before = await upkeeper.check();
      check(before.state).equals(UpkeepState.outdated);
      check(before.summary).contains('2 stale agy backup(s)');
      check(before.details).any(.it()..contains('agy.1795302543087764083.old'));

      final res = await upkeeper.update();
      check(res.success).isTrue;
      check(res.message).contains('Removed 2 stale agy backup(s)');
      check(stale1.existsSync()).isFalse;
      check(stale2.existsSync()).isFalse;
      check(File('${binDir.path}/agy').existsSync()).isTrue;

      final after = await upkeeper.check();
      check(after.state).equals(UpkeepState.upToDate);
    });

    test(
      'update still removes stale agy backups when untracked files also exist',
      () async {
        final stale = File('${binDir.path}/agy.999.old')
          ..writeAsStringSync('old');
        File('${binDir.path}/mystery-script').writeAsStringSync('#!/bin/sh\n');

        final upkeeper = LocalBinUpkeeper(
          homeDirOverride: () => tempHome.path,
          processRunner: (_, _) async => ProcessResult(0, 0, '', ''),
        );

        final status = await upkeeper.check();
        check(status.state).equals(UpkeepState.outdated);
        check(status.summary).contains('1 untracked, 1 stale agy backup(s)');

        final res = await upkeeper.update();
        check(res.success).isTrue;
        check(res.message).contains('Removed 1 stale agy backup(s)');
        check(res.message).contains('manual triage still needed');
        check(stale.existsSync()).isFalse;

        final after = await upkeeper.check();
        check(after.state).equals(UpkeepState.needsTriage);
      },
    );
  });
}
