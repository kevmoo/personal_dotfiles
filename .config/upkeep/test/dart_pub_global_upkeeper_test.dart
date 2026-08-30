import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('DartPubGlobalUpkeeper', () {
    test('isSupported returns true when dart binary exists', () async {
      final upkeeper = DartPubGlobalUpkeeper(
        processRunner: (executable, args) async {
          if (executable == 'dart' && args.contains('--version')) {
            return ProcessResult(0, 0, 'Dart SDK version: 3.10.0', '');
          }
          return ProcessResult(0, 1, '', 'not found');
        },
      );

      check(await upkeeper.isSupported()).isTrue();
    });

    test('check returns upToDate when no global packages exist', () async {
      final upkeeper = DartPubGlobalUpkeeper(
        processRunner: (executable, args) async {
          if (executable == 'dart' && args.contains('list')) {
            return ProcessResult(0, 0, '', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).equals('No legacy pub global packages found');
    });

    test(
      'check returns outdated and lists manual deactivation commands',
      () async {
        final upkeeper = DartPubGlobalUpkeeper(
          processRunner: (executable, args) async {
            if (executable == 'dart' && args.contains('list')) {
              return ProcessResult(
                0,
                0,
                'pub_release 1.0.0\nmelos 3.0.0 (from git https://github.com/invertase/melos.git)\n',
                '',
              );
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        final status = await upkeeper.check();
        check(status.state).equals(UpkeepState.outdated);
        check(status.summary)
            .equals('Found 2 legacy global package(s): pub_release, melos');
        check(status.details)
            .contains('  dart pub global deactivate pub_release');
        check(status.details).contains('  dart pub global deactivate melos');
      },
    );

    test('update deactivates legacy packages sequentially', () async {
      final executedArgs = <List<String>>[];
      final upkeeper = DartPubGlobalUpkeeper(
        processRunner: (executable, args) async {
          executedArgs.add([executable, ...args]);
          if (executable == 'dart' && args.contains('list')) {
            return ProcessResult(0, 0, 'pub_release 1.0.0\nmelos 3.0.0\n', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update();
      check(result.success).isTrue();
      check(result.message)
          .contains('Successfully deactivated 2 legacy global package(s)');

      check(
        executedArgs.any(
          (cmd) =>
              cmd.length >= 4 &&
              cmd[0] == 'dart' &&
              cmd[1] == 'pub' &&
              cmd[2] == 'global' &&
              cmd[3] == 'deactivate' &&
              cmd[4] == 'pub_release',
        ),
      ).isTrue();

      check(
        executedArgs.any(
          (cmd) =>
              cmd.length >= 4 &&
              cmd[0] == 'dart' &&
              cmd[1] == 'pub' &&
              cmd[2] == 'global' &&
              cmd[3] == 'deactivate' &&
              cmd[4] == 'melos',
        ),
      ).isTrue();
    });
  });
}
