import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('VscodeUpkeeper Symlinking', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('vscode_upkeep_test_');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('skips with message on macOS', () async {
      final upkeeper = VscodeUpkeeper(
        homeDirOverride: tempHome.path,
        isLinuxOverride: false,
        isMacOverride: true,
        isCloudtopOverride: false,
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.skipped);
      check(status.summary).equals('TODO - implement the list');

      final result = await upkeeper.update();
      check(result.success).isTrue();
      check(result.message).equals('TODO - implement the list');
    });

    test('skips if shared settings files do not exist', () async {
      final upkeeper = VscodeUpkeeper(
        homeDirOverride: tempHome.path,
        isLinuxOverride: true,
        isMacOverride: false,
        isCloudtopOverride: false,
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.skipped);
      check(status.summary)
          .contains('Shared vscode configuration files not found');
    });

    test('reconciles symlinks on Linux', () async {
      // 1. Set up shared settings source files
      final sharedDir = Directory('${tempHome.path}/.config/vscode-shared');
      sharedDir.createSync(recursive: true);
      File('${sharedDir.path}/settings.json')
          .writeAsStringSync('{"shared": true}');
      File('${sharedDir.path}/keybindings.json').writeAsStringSync('[]');

      // 2. Set up a target editor directory with an existing regular file (to be backed up)
      final codeUserDir = Directory('${tempHome.path}/.config/Code/User');
      codeUserDir.createSync(recursive: true);
      File('${codeUserDir.path}/settings.json')
          .writeAsStringSync('{"local": true}');

      final upkeeper = VscodeUpkeeper(
        homeDirOverride: tempHome.path,
        isLinuxOverride: true,
        isMacOverride: false,
        isCloudtopOverride: false,
      );

      // check() should report outdated because settings.json is a regular file and keybindings.json is missing
      final status1 = await upkeeper.check();
      check(status1.state).equals(UpkeepState.outdated);
      check(status1.details.length).equals(2);

      // Run update() to reconcile
      final result = await upkeeper.update();
      check(result.success).isTrue();

      // Check that settings.json.bak was created and settings.json is now a symlink pointing to the shared source
      final backupSettings = File('${codeUserDir.path}/settings.json.bak');
      check(backupSettings.existsSync()).isTrue();
      check(backupSettings.readAsStringSync()).equals('{"local": true}');

      final settingsLink = Link('${codeUserDir.path}/settings.json');
      check(settingsLink.existsSync()).isTrue();
      check(FileSystemEntity.isLinkSync(settingsLink.path)).isTrue();
      check(settingsLink.targetSync())
          .equals('../../vscode-shared/settings.json');

      final keybindingsLink = Link('${codeUserDir.path}/keybindings.json');
      check(keybindingsLink.existsSync()).isTrue();
      check(FileSystemEntity.isLinkSync(keybindingsLink.path)).isTrue();
      check(keybindingsLink.targetSync())
          .equals('../../vscode-shared/keybindings.json');

      // Now check() should return upToDate
      final status2 = await upkeeper.check();
      check(status2.state).equals(UpkeepState.upToDate);
    });

    test('isSupported is false without shared vscode config', () async {
      final upkeeper = VscodeUpkeeper(
        homeDirOverride: tempHome.path,
        isCloudtopOverride: false,
      );

      check(await upkeeper.isSupported()).isFalse();
    });

    test('isSupported is true when shared vscode config exists', () async {
      final sharedDir = Directory('${tempHome.path}/.config/vscode-shared');
      sharedDir.createSync(recursive: true);
      File('${sharedDir.path}/settings.json').writeAsStringSync('{}');
      File('${sharedDir.path}/keybindings.json').writeAsStringSync('[]');

      final upkeeper = VscodeUpkeeper(
        homeDirOverride: tempHome.path,
        isCloudtopOverride: false,
      );

      check(await upkeeper.isSupported()).isTrue();
    });
  });
}
