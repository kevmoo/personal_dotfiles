import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('DartInstallUpkeeper', () {
    late Directory tempInstallDir;

    setUp(() async {
      tempInstallDir = await Directory.systemTemp.createTemp(
        'dart_install_test_',
      );
    });

    tearDown(() async {
      if (tempInstallDir.existsSync()) {
        await tempInstallDir.delete(recursive: true);
      }
    });

    test('isSupported returns true when app-bundles exists', () async {
      final bundlesDir = Directory('${tempInstallDir.path}/app-bundles');
      bundlesDir.createSync(recursive: true);

      final upkeeper = DartInstallUpkeeper(installDirOverride: tempInstallDir);

      check(await upkeeper.isSupported()).isTrue();
    });

    test('isSupported returns false when app-bundles does not exist', () async {
      final upkeeper = DartInstallUpkeeper(installDirOverride: tempInstallDir);

      check(await upkeeper.isSupported()).isFalse();
    });

    test('check detects up to date hosted packages', () async {
      final hostedDir = Directory(
        '${tempInstallDir.path}/app-bundles/dhttpd/hosted/4.3.0',
      );
      hostedDir.createSync(recursive: true);

      final upkeeper = DartInstallUpkeeper(
        installDirOverride: tempInstallDir,
        versionFetcher: (pkg) async => '4.3.0',
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).contains('1 tool(s) up to date (dhttpd)');
    });

    test('check detects outdated hosted packages', () async {
      final hostedDir = Directory(
        '${tempInstallDir.path}/app-bundles/dhttpd/hosted/4.3.0',
      );
      hostedDir.createSync(recursive: true);

      final upkeeper = DartInstallUpkeeper(
        installDirOverride: tempInstallDir,
        versionFetcher: (pkg) async => '4.4.0',
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).equals('1 tool(s) outdated (dhttpd)');
      check(status.details).contains('  • dhttpd: 4.3.0 -> 4.4.0');
    });

    test('check detects outdated git packages', () async {
      final gitDir = Directory(
        '${tempInstallDir.path}/app-bundles/kevmoo_scripts/git/b798a52a0d713b5369d02ee30600482826481146',
      );
      gitDir.createSync(recursive: true);

      final pubspecLock = File('${gitDir.path}/pubspec.lock');
      pubspecLock.writeAsStringSync('''
packages:
  kevmoo_scripts:
    description:
      url: "https://github.com/kevmoo/scripts.dart.git"
''');

      final upkeeper = DartInstallUpkeeper(
        installDirOverride: tempInstallDir,
        processRunner: (executable, args) async {
          if (executable == 'git' && args.contains('ls-remote')) {
            return ProcessResult(
              0,
              0,
              'ed6acf3d2e2482d0f750b97df8ddc00196a244fc\tHEAD',
              '',
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).equals('1 tool(s) outdated (kevmoo_scripts)');
      check(status.details)
          .contains('  • kevmoo_scripts (git): b798a52 -> ed6acf3');
    });

    test('update executes dart install for outdated hosted packages', () async {
      final hostedDir = Directory(
        '${tempInstallDir.path}/app-bundles/dhttpd/hosted/4.3.0',
      );
      hostedDir.createSync(recursive: true);

      final executedArgs = <List<String>>[];
      final upkeeper = DartInstallUpkeeper(
        installDirOverride: tempInstallDir,
        versionFetcher: (pkg) async => '4.4.0',
        processRunner: (executable, args) async {
          executedArgs.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );

      final result = await upkeeper.update();
      check(result.success).isTrue();
      check(result.message)
          .contains('Successfully updated 1 Dart tool(s): dhttpd');

      check(
        executedArgs.any(
          (cmd) =>
              cmd.length == 3 &&
              cmd[0] == 'dart' &&
              cmd[1] == 'install' &&
              cmd[2] == 'dhttpd',
        ),
      ).isTrue();
    });
  });
}
