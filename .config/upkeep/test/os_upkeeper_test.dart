import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('OsUpkeeper & GlinuxOsStrategy', () {
    test(
      'GlinuxOsStrategy detects active gCert and returns upToDate',
      () async {
        final strategy = GlinuxOsStrategy(
          rebootRequiredChecker: () => false,
          processRunner: (executable, args) async {
            if (executable == 'gcertstatus') {
              return ProcessResult(0, 0, 'LOAS2 expires in 16h 53m', '');
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        final status = await strategy.check('os', 'OS System Updates');
        check(status.state).equals(UpkeepState.upToDate);
        check(status.summary).contains('gLinux Cloudtop system is up to date');
      },
    );

    test(
      'GlinuxOsStrategy flags actionRequired when gCert expires soon',
      () async {
        final strategy = GlinuxOsStrategy(
          rebootRequiredChecker: () => false,
          processRunner: (executable, args) async {
            if (executable == 'gcertstatus') {
              return ProcessResult(0, 0, 'LOAS2 expires in 2h 15m', '');
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        final status = await strategy.check('os', 'OS System Updates');
        check(status.state).equals(UpkeepState.outdated);
        check(status.summary)
            .contains('gCert ticket expiring soon (2h remaining)');
      },
    );

    test(
      'GlinuxOsStrategy flags actionRequired when gCert check fails',
      () async {
        final strategy = GlinuxOsStrategy(
          rebootRequiredChecker: () => false,
          processRunner: (executable, args) async {
            if (executable == 'gcertstatus') {
              return ProcessResult(1, 1, '', 'No valid ticket found');
            }
            return ProcessResult(0, 0, '', '');
          },
        );

        final status = await strategy.check('os', 'OS System Updates');
        check(status.state).equals(UpkeepState.outdated);
        check(status.summary).contains('gCert ticket inactive or expired');
      },
    );

    test('GlinuxOsStrategy flags actionRequired when reboot required flag is active', () async {
      final strategy = GlinuxOsStrategy(
        rebootRequiredChecker: () => true,
        processRunner: (executable, args) async {
          if (executable == 'gcertstatus') {
            return ProcessResult(0, 0, 'LOAS2 expires in 16h 53m', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await strategy.check('os', 'OS System Updates');
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('System reboot required');
    });

    test('GlinuxOsStrategy update runs sudo glinux-updater -vF and reports reboot warning if required', () async {
      final commandsRun = <String>[];
      final strategy = GlinuxOsStrategy(
        rebootRequiredChecker: () => true,
        processRunner: (executable, args) async {
          commandsRun.add('$executable ${args.join(' ')}'.trim());
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await strategy.update('os', 'OS System Updates');
      check(result.success).isTrue();
      check(commandsRun).deepEquals(['gcert', 'sudo glinux-updater -vF']);
      check(result.message).contains('WARNING: System reboot required');
    });
  });
}
