import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('DoltUpkeeper', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('dolt_upkeep_test_');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('detects outdated Dolt when warning is present', () async {
      final dummyDolt = File('${tempHome.path}/dolt')
        ..createSync(recursive: true);
      final upkeeper = DoltUpkeeper(
        doltPathOverride: dummyDolt.path,
        processRunner: (executable, args) async {
          if (args.contains('version')) {
            return ProcessResult(
              0,
              0,
              'dolt version 2.1.6\nWarning: you are on an old version of Dolt. The newest version is 2.1.10.',
              '',
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('Dolt update available -> 2.1.10');
    });

    test(
      'isSupported returns false when Homebrew is installed on non-cloudtop',
      () async {
        final dummyDolt = File('${tempHome.path}/dolt')
          ..createSync(recursive: true);
        final upkeeper = DoltUpkeeper(
          doltPathOverride: dummyDolt.path,
          isCloudtopOverride: false,
          processRunner: (executable, args) async {
            if (executable == 'which' && args.contains('brew')) {
              return ProcessResult(0, 0, '/usr/local/bin/brew\n', '');
            }
            return ProcessResult(1, 1, '', '');
          },
        );

        final supported = await upkeeper.isSupported();
        check(supported).isFalse();
      },
    );

    test(
      'isSupported returns true on cloudtop even when Homebrew is installed',
      () async {
        final dummyDolt = File('${tempHome.path}/dolt')
          ..createSync(recursive: true);
        final upkeeper = DoltUpkeeper(
          doltPathOverride: dummyDolt.path,
          isCloudtopOverride: true,
          processRunner: (executable, args) async {
            if (executable == 'which' && args.contains('brew')) {
              return ProcessResult(0, 0, '/usr/local/bin/brew\n', '');
            }
            return ProcessResult(1, 1, '', '');
          },
        );

        final supported = await upkeeper.isSupported();
        check(supported).isTrue();
      },
    );

    test('check returns outdated on cloudtop when binary is missing', () async {
      final upkeeper = DoltUpkeeper(
        doltPathOverride: '${tempHome.path}/nonexistent_dolt',
        isCloudtopOverride: true,
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('Dolt binary not installed');
    });

    test('detects up to date Dolt when no warning is present', () async {
      final dummyDolt = File('${tempHome.path}/dolt')
        ..createSync(recursive: true);
      final upkeeper = DoltUpkeeper(
        doltPathOverride: dummyDolt.path,
        processRunner: (executable, args) async {
          if (args.contains('version')) {
            return ProcessResult(0, 0, 'dolt version 2.1.10', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).contains('Dolt binary is up to date');
    });
  });
}
