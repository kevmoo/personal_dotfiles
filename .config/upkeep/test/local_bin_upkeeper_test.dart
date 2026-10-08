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
      check(await upkeeper.isSupported()).isTrue();
    });

    test('isSupported is false when ~/.local/bin is absent', () async {
      binDir.deleteSync(recursive: true);
      final upkeeper = LocalBinUpkeeper(homeDirOverride: () => tempHome.path);
      check(await upkeeper.isSupported()).isFalse();
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
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('2 untracked, 1 broken symlink(s)');
      check(status.details).any((d) => d.contains('mystery-script'));
      check(status.details).any(
        (d) => d
          ..contains('broken-link')
          ..contains('broken symlink'),
      );

      final updateRes = await upkeeper.update();
      check(updateRes.success).isFalse();
      check(updateRes.message).contains('Manual triage required');
    });
  });
}
