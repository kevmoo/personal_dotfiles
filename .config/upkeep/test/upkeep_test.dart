import 'dart:io';

import 'package:checks/checks.dart';
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
  });
}
