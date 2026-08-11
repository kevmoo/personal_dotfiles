import 'dart:io';

import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('FlutterRepoUpkeeper', () {
    late Directory tempDir;
    late Directory flutterDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_upkeeper_test_');
      flutterDir = Directory(p.join(tempDir.path, 'github', 'flutter'));
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('isSupported is false when no .git exists', () async {
      final upkeeper = FlutterRepoUpkeeper(overrideFlutterDir: flutterDir);
      check(await upkeeper.isSupported()).isFalse();
    });

    test('isSupported is true when .git exists', () async {
      Directory(p.join(flutterDir.path, '.git')).createSync(recursive: true);
      final upkeeper = FlutterRepoUpkeeper(overrideFlutterDir: flutterDir);
      check(await upkeeper.isSupported()).isTrue();
    });

    test('check returns outdated when branch is not master or main', () async {
      Directory(p.join(flutterDir.path, '.git')).createSync(recursive: true);
      final upkeeper = FlutterRepoUpkeeper(
        overrideFlutterDir: flutterDir,
        processRunner: (executable, args) async {
          if (args.contains('rev-parse')) {
            return ProcessResult(0, 0, 'HEAD\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('Not on master/main branch');
    });

    test(
      'check returns outdated when commits behind > 0 or age > 72 hours',
      () async {
        Directory(p.join(flutterDir.path, '.git')).createSync(recursive: true);
        final fourDaysAgoSecs =
            DateTime.now()
                .subtract(const Duration(days: 4))
                .millisecondsSinceEpoch ~/
            1000;

        final upkeeper = FlutterRepoUpkeeper(
          overrideFlutterDir: flutterDir,
          processRunner: (executable, args) async {
            if (args.contains('rev-parse')) {
              return ProcessResult(0, 0, 'master\n', '');
            }
            if (args.contains('rev-list')) {
              return ProcessResult(0, 0, '5\n', '');
            }
            if (args.contains('log')) {
              return ProcessResult(0, 0, '$fourDaysAgoSecs\n', '');
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        final status = await upkeeper.check();
        check(status.state).equals(UpkeepState.outdated);
        check(status.summary).contains('5 commits behind origin/master');
        check(status.summary).contains('4 days old');
      },
    );

    test(
      'check returns upToDate when 0 commits behind and HEAD is < 72 hours old',
      () async {
        Directory(p.join(flutterDir.path, '.git')).createSync(recursive: true);
        final twoHoursAgoSecs =
            DateTime.now()
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch ~/
            1000;

        final upkeeper = FlutterRepoUpkeeper(
          overrideFlutterDir: flutterDir,
          processRunner: (executable, args) async {
            if (args.contains('rev-parse')) {
              return ProcessResult(0, 0, 'master\n', '');
            }
            if (args.contains('rev-list')) {
              return ProcessResult(0, 0, '0\n', '');
            }
            if (args.contains('log')) {
              return ProcessResult(0, 0, '$twoHoursAgoSecs\n', '');
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        final status = await upkeeper.check();
        check(status.state).equals(UpkeepState.upToDate);
        check(status.summary).contains('Up to date on master');
        check(status.summary).contains('0 commits behind');
      },
    );

    test('update fails when working tree has uncommitted changes', () async {
      Directory(p.join(flutterDir.path, '.git')).createSync(recursive: true);
      final upkeeper = FlutterRepoUpkeeper(
        overrideFlutterDir: flutterDir,
        processRunner: (executable, args) async {
          if (args.contains('status')) {
            return ProcessResult(0, 0, ' M lib/main.dart\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update();
      check(result.success).isFalse();
      check(result.message).contains('uncommitted local changes exist');
    });

    test('update performs checkout and pull when clean', () async {
      Directory(p.join(flutterDir.path, '.git')).createSync(recursive: true);
      final commands = <String>[];
      final upkeeper = FlutterRepoUpkeeper(
        overrideFlutterDir: flutterDir,
        processRunner: (executable, args) async {
          commands.add('$executable ${args.join(' ')}');
          if (args.contains('status')) {
            return ProcessResult(0, 0, '', '');
          }
          if (args.contains('rev-parse')) {
            return ProcessResult(0, 0, 'master\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update();
      check(result.success).isTrue();
      check(commands)
          .contains('git -C ${flutterDir.path} pull --ff-only origin master');
    });
  });
}
