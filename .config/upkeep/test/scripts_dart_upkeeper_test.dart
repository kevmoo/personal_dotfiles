import 'dart:io';

import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
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

    void createMockInstallDir(String resolvedRef) {
      final gitDir = Directory(
        '${tempPubCache.path}/app-bundles/kevmoo_scripts/git/$resolvedRef',
      );
      gitDir.createSync(recursive: true);
    }

    test('detects update available when local SHA != remote SHA', () async {
      createMockInstallDir('b798a52a0d713b5369d02ee30600482826481146');

      final upkeeper = ScriptsDartUpkeeper(
        pubCacheDirOverride: tempPubCache,
        installDirOverride: tempPubCache,
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
      createMockInstallDir('ed6acf3d2e2482d0f750b97df8ddc00196a244fc');

      final upkeeper = ScriptsDartUpkeeper(
        pubCacheDirOverride: tempPubCache,
        installDirOverride: tempPubCache,
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
      final upkeeper = ScriptsDartUpkeeper(
        pubCacheDirOverride: tempPubCache,
        installDirOverride: tempPubCache,
      );

      final status = await upkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(status.summary).equals('scripts package not installed');
    });

    test('isSupported is false when not activated globally', () async {
      final upkeeper = ScriptsDartUpkeeper(
        pubCacheDirOverride: tempPubCache,
        installDirOverride: tempPubCache,
      );

      check(await upkeeper.isSupported()).isFalse();
    });

    test('isSupported is true when activated globally', () async {
      createMockInstallDir('ed6acf3d2e2482d0f750b97df8ddc00196a244fc');
      final upkeeper = ScriptsDartUpkeeper(
        pubCacheDirOverride: tempPubCache,
        installDirOverride: tempPubCache,
      );

      check(await upkeeper.isSupported()).isTrue();
    });
  });
}
