import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('DotfilesCorpUpkeeper', () {
    late Directory tempHome;
    late Directory dotfilesCorpDir;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('dotfiles_corp_test_');
      dotfilesCorpDir = Directory('${tempHome.path}/.dotfiles-corp');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('isSupported is true on Cloudtop', () async {
      final upkeeper = DotfilesCorpUpkeeper(isCloudtopOverride: true);
      check(await upkeeper.isSupported()).isTrue();
    });

    test('isSupported is false on non-Cloudtop', () async {
      final upkeeper = DotfilesCorpUpkeeper(isCloudtopOverride: false);
      check(await upkeeper.isSupported()).isFalse();
    });

    test('check returns error when directory does not exist', () async {
      final upkeeper = DotfilesCorpUpkeeper(
        isCloudtopOverride: true,
        homeDirOverride: () => tempHome.path,
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.error);
      check(status.summary).contains('Private dotfiles directory not found');
    });

    test('check returns outdated when dirty', () async {
      dotfilesCorpDir.createSync(recursive: true);
      final upkeeper = DotfilesCorpUpkeeper(
        isCloudtopOverride: true,
        homeDirOverride: () => tempHome.path,
        processRunner: (executable, args) async {
          if (args.contains('status')) {
            return ProcessResult(0, 0, ' M some_file.txt\n', '');
          }
          if (args.contains('fetch')) {
            return ProcessResult(0, 0, '', '');
          }
          if (args.contains('rev-parse')) {
            return ProcessResult(1, 1, '', ''); // No upstream
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('uncommitted changes');
      check(status.details).isNotNull().contains('M some_file.txt');
    });

    test('check returns error when fetch fails', () async {
      dotfilesCorpDir.createSync(recursive: true);
      final upkeeper = DotfilesCorpUpkeeper(
        isCloudtopOverride: true,
        homeDirOverride: () => tempHome.path,
        processRunner: (executable, args) async {
          if (args.contains('status')) {
            return ProcessResult(0, 0, '', ''); // Clean
          }
          if (args.contains('fetch')) {
            return ProcessResult(1, 1, '', 'Fetch timeout');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.error);
      check(status.summary).contains('Error fetching remote updates');
      check(status.errorMessage).isNotNull().contains('Fetch timeout');
    });

    test('check returns outdated when behind or ahead', () async {
      dotfilesCorpDir.createSync(recursive: true);
      final upkeeper = DotfilesCorpUpkeeper(
        isCloudtopOverride: true,
        homeDirOverride: () => tempHome.path,
        processRunner: (executable, args) async {
          if (args.contains('status')) {
            return ProcessResult(0, 0, '', ''); // Clean
          }
          if (args.contains('fetch')) {
            return ProcessResult(0, 0, '', '');
          }
          if (args.contains('rev-parse')) {
            return ProcessResult(0, 0, 'origin/main\n', ''); // Has upstream
          }
          if (args.contains('rev-list')) {
            if (args.contains('HEAD..@{u}')) {
              return ProcessResult(0, 0, '2\n', ''); // 2 behind
            }
            if (args.contains('@{u}..HEAD')) {
              return ProcessResult(0, 0, '1\n', ''); // 1 ahead
            }
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('2 behind, 1 ahead');
      check(status.details)
          .isNotNull()
          .contains('2 new commit(s) available on remote');
      check(status.details).isNotNull().contains('1 local commit(s) unpushed');
    });

    test('update fails when dirty', () async {
      dotfilesCorpDir.createSync(recursive: true);
      final upkeeper = DotfilesCorpUpkeeper(
        isCloudtopOverride: true,
        homeDirOverride: () => tempHome.path,
        processRunner: (executable, args) async {
          if (args.contains('status')) {
            return ProcessResult(0, 0, ' M some_file.txt\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update();
      check(result.success).isFalse();
      check(result.message).contains('uncommitted changes');
    });

    test('update pulls and pushes when clean', () async {
      dotfilesCorpDir.createSync(recursive: true);
      final commands = <String>[];
      final upkeeper = DotfilesCorpUpkeeper(
        isCloudtopOverride: true,
        homeDirOverride: () => tempHome.path,
        processRunner: (executable, args) async {
          commands.add('$executable ${args.join(' ')}');
          if (args.contains('status')) {
            return ProcessResult(0, 0, '', ''); // Clean
          }
          if (args.contains('rev-parse')) {
            return ProcessResult(0, 0, 'origin/main\n', ''); // Has upstream
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update();
      check(result.success).isTrue();
      check(commands).contains(
        'git --git-dir=${dotfilesCorpDir.path} --work-tree=${tempHome.path} pull --rebase',
      );
      check(commands).contains(
        'git --git-dir=${dotfilesCorpDir.path} --work-tree=${tempHome.path} push',
      );
    });

    test('check and update invoke dotcorp-upkeep-hook when present', () async {
      dotfilesCorpDir.createSync(recursive: true);
      final hookFile = File('${tempHome.path}/.local/bin/dotcorp-upkeep-hook')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/bash\n');

      var hookCheckExit = 10;
      var hookCheckStdout = 'OUTDATED: 1 upstream file changed\n';
      final invoked = <String>[];

      final upkeeper = DotfilesCorpUpkeeper(
        isCloudtopOverride: true,
        homeDirOverride: () => tempHome.path,
        processRunner: (executable, args) async {
          invoked.add('$executable ${args.join(' ')}');
          if (executable == hookFile.path) {
            if (args.contains('check')) {
              return ProcessResult(0, hookCheckExit, hookCheckStdout, '');
            }
            if (args.contains('update')) {
              return ProcessResult(0, 0, 'APPLIED\n', '');
            }
          }
          if (args.contains('status')) {
            return ProcessResult(0, 0, '', ''); // Clean
          }
          if (args.contains('rev-parse')) {
            return ProcessResult(0, 0, 'origin/main\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      // 1. Exit 10 -> UpkeepState.outdated
      final outdatedStatus = await upkeeper.check();
      check(outdatedStatus.state).equals(UpkeepState.outdated);
      check(outdatedStatus.summary).contains('hook outdated');
      check(outdatedStatus.details)
          .isNotNull()
          .contains('OUTDATED: 1 upstream file changed');

      // 2. Exit 20 -> UpkeepState.error
      hookCheckExit = 20;
      hookCheckStdout = 'ANCHOR_CONFLICT: SKILL.md missing anchor\n';
      final errorStatus = await upkeeper.check();
      check(errorStatus.state).equals(UpkeepState.error);
      check(errorStatus.summary).contains('hook check failed');
      check(errorStatus.errorMessage)
          .isNotNull()
          .contains('ANCHOR_CONFLICT: SKILL.md missing anchor');

      // 3. Exit 0 -> UpkeepState.upToDate
      hookCheckExit = 0;
      hookCheckStdout = 'OK\n';
      final okStatus = await upkeeper.check();
      check(okStatus.state).equals(UpkeepState.upToDate);

      // 4. Update runs hook update
      final updateRes = await upkeeper.update();
      check(updateRes.success).isTrue();
      check(invoked).contains('${hookFile.path} update');
    });

    test(
      'update runs dotcorp-upkeep-hook even when git repo is dirty',
      () async {
        dotfilesCorpDir.createSync(recursive: true);
        final hookFile = File('${tempHome.path}/.local/bin/dotcorp-upkeep-hook')
          ..createSync(recursive: true)
          ..writeAsStringSync('#!/bin/bash\n');
        final invoked = <String>[];

        final upkeeper = DotfilesCorpUpkeeper(
          isCloudtopOverride: true,
          homeDirOverride: () => tempHome.path,
          processRunner: (executable, args) async {
            invoked.add('$executable ${args.join(' ')}');
            if (args.contains('status')) {
              return ProcessResult(
                0,
                0,
                ' M .config/dotfiles-corp/deep_review_overlay/overlay_spec.json\n',
                '',
              );
            }
            return ProcessResult(0, 0, 'APPLIED\n', '');
          },
        );

        final result = await upkeeper.update();
        check(result.success).isTrue();
        check(result.message).contains('hook updated');
        check(invoked).contains('${hookFile.path} update');
      },
    );
  });
}
