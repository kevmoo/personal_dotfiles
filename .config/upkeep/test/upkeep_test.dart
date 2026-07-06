import 'dart:io';

import 'package:checks/checks.dart';
import 'package:io/ansi.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

class MockUpkeeper implements Upkeeper {
  @override
  final String id;
  @override
  final String displayName;
  final bool supported;
  final UpkeepStatus statusToReturn;

  MockUpkeeper({
    required this.id,
    required this.displayName,
    this.supported = true,
    required this.statusToReturn,
  });

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<UpkeepStatus> check() async => statusToReturn;

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    return UpkeepResult(
      upkeeperId: id,
      displayName: displayName,
      success: true,
      message: 'Mock update succeeded',
    );
  }
}

void main() {
  group('Upkeep Models & Serialization', () {
    test('UpkeepStatus toJson serialization', () {
      final status = UpkeepStatus(
        upkeeperId: 'test_id',
        displayName: 'Test Subsystem',
        state: UpkeepState.outdated,
        summary: '2 updates pending',
        details: ['Item A', 'Item B'],
      );

      final json = status.toJson();
      check(json['id']).equals('test_id');
      check(json['state']).equals('outdated');
      check(json['summary']).equals('2 updates pending');
      check((json['details'] as List).length).equals(2);
    });
  });

  group('TableFormatter Output', () {
    test(
      'prints update command when subsystem status is outdated (yellow)',
      () {
        overrideAnsiOutput(true, () {
          final status = UpkeepStatus(
            upkeeperId: 'brew',
            displayName: 'Homebrew Package Upgrades',
            state: UpkeepState.outdated,
            summary: '1 formula outdated',
          );

          final expectedCmd = wrapWith('upkeep update brew', [styleBold, blue]);
          final table = TableFormatter.formatStatusTable([status]);
          check(table).contains('Command: $expectedCmd');
        });
      },
    );

    test(
      'does not print update command when subsystem status is upToDate (green)',
      () {
        final status = UpkeepStatus(
          upkeeperId: 'brew',
          displayName: 'Homebrew Package Upgrades',
          state: UpkeepState.upToDate,
          summary: 'Up to date',
        );

        final table = TableFormatter.formatStatusTable([status]);
        check(table).not((c) => c.contains('Command: upkeep update'));
      },
    );
  });

  group('UpkeepRunner Concurrent Execution', () {
    test(
      'Runner filters unsupported upkeepers and checks in parallel',
      () async {
        final mock1 = MockUpkeeper(
          id: 'supported_1',
          displayName: 'Supported 1',
          supported: true,
          statusToReturn: const UpkeepStatus(
            upkeeperId: 'supported_1',
            displayName: 'Supported 1',
            state: UpkeepState.upToDate,
            summary: 'All clear',
          ),
        );

        final mock2 = MockUpkeeper(
          id: 'unsupported_1',
          displayName: 'Unsupported 1',
          supported: false,
          statusToReturn: const UpkeepStatus(
            upkeeperId: 'unsupported_1',
            displayName: 'Unsupported 1',
            state: UpkeepState.skipped,
            summary: 'Skipped',
          ),
        );

        final runner = UpkeepRunner(upkeepers: [mock1, mock2]);
        final statuses = await runner.checkAll();

        check(statuses.length).equals(1);
        check(statuses.first.upkeeperId).equals('supported_1');
        check(statuses.first.state).equals(UpkeepState.upToDate);
      },
    );

    test('Runner filters by targetIds in checkAll', () async {
      final mock1 = MockUpkeeper(
        id: 'brew',
        displayName: 'Brew Subsystem',
        statusToReturn: const UpkeepStatus(
          upkeeperId: 'brew',
          displayName: 'Brew Subsystem',
          state: UpkeepState.upToDate,
          summary: 'All clear',
        ),
      );

      final mock2 = MockUpkeeper(
        id: 'mise',
        displayName: 'Mise Subsystem',
        statusToReturn: const UpkeepStatus(
          upkeeperId: 'mise',
          displayName: 'Mise Subsystem',
          state: UpkeepState.outdated,
          summary: 'Outdated',
        ),
      );

      final runner = UpkeepRunner(upkeepers: [mock1, mock2]);
      final statuses = await runner.checkAll(targetIds: ['brew']);

      check(statuses.length).equals(1);
      check(statuses.first.upkeeperId).equals('brew');
    });

    test('Runner executes selected updates', () async {
      final mock1 = MockUpkeeper(
        id: 'sub1',
        displayName: 'Subsystem 1',
        statusToReturn: const UpkeepStatus(
          upkeeperId: 'sub1',
          displayName: 'Subsystem 1',
          state: UpkeepState.outdated,
          summary: 'Outdated',
        ),
      );

      final runner = UpkeepRunner(upkeepers: [mock1]);
      final updateResults = await runner.updateSelected(['sub1']);

      check(updateResults.length).equals(1);
      check(updateResults.first.success).isTrue();
      check(updateResults.first.upkeeperId).equals('sub1');
    });
  });

  group('ScriptsDartUpkeeper SHA Comparison', () {
    late Directory tempPubCache;

    setUp(() async {
      tempPubCache = await Directory.systemTemp.createTemp('pub_cache_test_');
    });

    tearDown(() async {
      if (tempPubCache.existsSync()) {
        await tempPubCache.delete(recursive: true);
      }
    });

    void createMockLockFile(String resolvedRef) {
      final pkgDir = Directory(
        '${tempPubCache.path}/global_packages/kevmoo_scripts',
      );
      pkgDir.createSync(recursive: true);
      final lockFile = File('${pkgDir.path}/pubspec.lock');
      lockFile.writeAsStringSync('''
packages:
  kevmoo_scripts:
    description:
      resolved-ref: "$resolvedRef"
      url: "https://github.com/kevmoo/scripts.dart"
    source: git
    version: "0.0.0"
''');
    }

    test('detects update available when local SHA != remote SHA', () async {
      createMockLockFile('b798a52a0d713b5369d02ee30600482826481146');

      final upkeeper = ScriptsDartUpkeeper(
        pubCacheDirOverride: tempPubCache,
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
      check(status.summary).equals('Update available: b798a52 -> ed6acf3');
    });

    test('detects up to date when local SHA == remote SHA', () async {
      createMockLockFile('ed6acf3d2e2482d0f750b97df8ddc00196a244fc');

      final upkeeper = ScriptsDartUpkeeper(
        pubCacheDirOverride: tempPubCache,
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
      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).equals('Up to date (ed6acf3)');
    });

    test('reports outdated if not activated globally', () async {
      final upkeeper = ScriptsDartUpkeeper(pubCacheDirOverride: tempPubCache);

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).equals('scripts package not activated globally');
    });

    test('isSupported is false when not activated globally', () async {
      final upkeeper = ScriptsDartUpkeeper(pubCacheDirOverride: tempPubCache);

      check(await upkeeper.isSupported()).isFalse();
    });

    test('isSupported is true when activated globally', () async {
      createMockLockFile('ed6acf3d2e2482d0f750b97df8ddc00196a244fc');
      final upkeeper = ScriptsDartUpkeeper(pubCacheDirOverride: tempPubCache);

      check(await upkeeper.isSupported()).isTrue();
    });
  });

  group('OsUpkeeper & GlinuxOsStrategy', () {
    test(
      'GlinuxOsStrategy detects active gCert and returns upToDate',
      () async {
        final strategy = GlinuxOsStrategy(
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
  });

  group('BeadsDoltUpkeeper', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('beads_upkeep_test_');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('detects outdated Dolt when warning is present', () async {
      final dummyDolt = File('${tempHome.path}/dolt')
        ..createSync(recursive: true);
      final upkeeper = BeadsDoltUpkeeper(
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

    test('isSupported returns false when Homebrew is installed', () async {
      final dummyDolt = File('${tempHome.path}/dolt')
        ..createSync(recursive: true);
      final upkeeper = BeadsDoltUpkeeper(
        doltPathOverride: dummyDolt.path,
        processRunner: (executable, args) async {
          if (executable == 'which' && args.contains('brew')) {
            return ProcessResult(0, 0, '/usr/local/bin/brew\n', '');
          }
          return ProcessResult(1, 1, '', '');
        },
      );

      final supported = await upkeeper.isSupported();
      check(supported).isFalse();
    });

    test('detects up to date Dolt when no warning is present', () async {
      final dummyDolt = File('${tempHome.path}/dolt')
        ..createSync(recursive: true);
      final upkeeper = BeadsDoltUpkeeper(
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
      check(status.summary).contains('Beads & Dolt binaries are up to date');
    });
  });

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
      final upkeeper = VscodeUpkeeper(homeDirOverride: tempHome.path);

      check(await upkeeper.isSupported()).isFalse();
    });

    test('isSupported is true when shared vscode config exists', () async {
      final sharedDir = Directory('${tempHome.path}/.config/vscode-shared');
      sharedDir.createSync(recursive: true);
      File('${sharedDir.path}/settings.json').writeAsStringSync('{}');
      File('${sharedDir.path}/keybindings.json').writeAsStringSync('[]');

      final upkeeper = VscodeUpkeeper(homeDirOverride: tempHome.path);

      check(await upkeeper.isSupported()).isTrue();
    });
  });

  group('SkillsUpkeeper', () {
    late Directory tempHome;

    setUp(() async {
      tempHome = await Directory.systemTemp.createTemp('skills_upkeep_test_');
    });

    tearDown(() async {
      if (tempHome.existsSync()) {
        await tempHome.delete(recursive: true);
      }
    });

    test('isSupported is false when no skills setup exists', () async {
      final upkeeper = SkillsUpkeeper(homeDirOverride: tempHome.path);

      check(await upkeeper.isSupported()).isFalse();
    });
  });

  group('GuacamoleUpkeeper', () {
    test('detects outdated containers when pending in auto-update', () async {
      final upkeeper = GuacamoleUpkeeper(
        processRunner: (executable, args) async {
          if (args.contains('auto-update')) {
            return ProcessResult(0, 0, '''
[
  {
    "Unit": "guac-pod.service",
    "Container": "922eb7b54c3f",
    "ContainerName": "guacamole",
    "Image": "docker.io/guacamole/guacamole:latest",
    "Policy": "registry",
    "Updated": "pending"
  }
]
''', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).contains('Updates available for: guacamole');
    });

    test('detects up to date when none pending', () async {
      final upkeeper = GuacamoleUpkeeper(
        processRunner: (executable, args) async {
          if (args.contains('auto-update')) {
            return ProcessResult(0, 0, '''
[
  {
    "Unit": "guac-pod.service",
    "Container": "b55eb6936f75",
    "ContainerName": "guacd",
    "Image": "docker.io/guacamole/guacd:latest",
    "Policy": "registry",
    "Updated": "false"
  }
]
''', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.upToDate);
      check(status.summary).contains('Guacamole stack is up to date');
    });
  });
}
