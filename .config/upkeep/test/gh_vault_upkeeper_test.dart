import 'dart:io';

import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:upkeep/src/models.dart';
import 'package:upkeep/src/upkeepers/gh_vault_upkeeper.dart';

void main() {
  group('GhVaultUpkeeper', () {
    late GhVaultUpkeeper upkeeper;

    setUp(() {
      upkeeper = GhVaultUpkeeper();
    });

    test('metadata', () {
      check(upkeeper.id).equals('gh_vault');
      check(upkeeper.displayName).equals('GitHub CLI Vault & Agent Safeguards');
    });

    test('isSupported returns true if ~/.config/gh_vault exists', () async {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      final exists = Directory(p.join(home, '.config', 'gh_vault'))
          .existsSync();
      check(await upkeeper.isSupported()).equals(exists);
    });

    test('check returns a valid UpkeepStatus', () async {
      if (!await upkeeper.isSupported()) return;

      final status = await upkeeper.check();
      check(status.upkeeperId).equals('gh_vault');
      check(status.state).anyOf([
        (s) => s.equals(UpkeepState.upToDate),
        (s) => s.equals(UpkeepState.outdated),
      ]);
    });

    test('detects stale user binary when lib source is newer', () async {
      final tempDir = Directory.systemTemp.createTempSync('gh_vault_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final fakePkg = Directory(p.join(tempDir.path, 'pkg'))
        ..createSync(recursive: true);
      final fakeLib = Directory(p.join(fakePkg.path, 'lib'))
        ..createSync(recursive: true);
      final fakeLocalBin = Directory(p.join(tempDir.path, '.local', 'bin'))
        ..createSync(recursive: true);
      final fakeEtc = Directory(p.join(tempDir.path, 'etc', 'github'))
        ..createSync(recursive: true);

      final vaultFile = File(p.join(fakeEtc.path, 'admin.token'))
        ..writeAsStringSync('token');
      final systemUnlock = File(
        p.join(tempDir.path, 'usr', 'local', 'bin', 'gh-unlock'),
      )..createSync(recursive: true);

      final dispatchBin = File(p.join(fakeLocalBin.path, 'gh'))
        ..writeAsStringSync('bin');
      final lockBin = File(p.join(fakeLocalBin.path, 'gh-lock'))
        ..writeAsStringSync('bin');
      final unlockBin = File(p.join(fakeLocalBin.path, 'gh-unlock'))
        ..writeAsStringSync('bin');

      // Set binary mtime to past
      final oldTime = DateTime.now().subtract(const Duration(hours: 2));
      dispatchBin.setLastModifiedSync(oldTime);
      lockBin.setLastModifiedSync(oldTime);
      unlockBin.setLastModifiedSync(oldTime);
      systemUnlock.setLastModifiedSync(oldTime);

      // Create a newer source file in lib/
      final sourceFile = File(p.join(fakeLib.path, 'paths.dart'))
        ..writeAsStringSync('// new source');
      sourceFile.setLastModifiedSync(DateTime.now());

      final customUpkeeper = GhVaultUpkeeper(
        homeDirOverride: tempDir.path,
        packageDirOverride: fakePkg.path,
        systemUnlockBinOverride: systemUnlock.path,
        rootVaultFileOverride: vaultFile.path,
        processRunner: (exec, args) async =>
            ProcessResult(0, 0, 'github_pat_valid', ''),
      );

      final status = await customUpkeeper.check();
      check(status.state).equals(UpkeepState.outdated);
      check(
        status.details.any((d) => d.contains('older than source Dart package')),
      ).isTrue();
    });

    test(
      'detects stale system unlock binary when user binary is newer',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'gh_vault_sys_test_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final fakePkg = Directory(p.join(tempDir.path, 'pkg'))
          ..createSync(recursive: true);
        final fakeLib = Directory(p.join(fakePkg.path, 'lib'))
          ..createSync(recursive: true);
        final fakeLocalBin = Directory(p.join(tempDir.path, '.local', 'bin'))
          ..createSync(recursive: true);
        final fakeEtc = Directory(p.join(tempDir.path, 'etc', 'github'))
          ..createSync(recursive: true);

        final vaultFile = File(p.join(fakeEtc.path, 'admin.token'))
          ..writeAsStringSync('token');
        final systemUnlock = File(
          p.join(tempDir.path, 'usr', 'local', 'bin', 'gh-unlock'),
        )..createSync(recursive: true);

        final dispatchBin = File(p.join(fakeLocalBin.path, 'gh'))
          ..writeAsStringSync('bin');
        final lockBin = File(p.join(fakeLocalBin.path, 'gh-lock'))
          ..writeAsStringSync('bin');
        final unlockBin = File(p.join(fakeLocalBin.path, 'gh-unlock'))
          ..writeAsStringSync('bin');

        final sourceTime = DateTime.now().subtract(const Duration(hours: 5));
        final sourceFile = File(p.join(fakeLib.path, 'paths.dart'))
          ..writeAsStringSync('// source');
        sourceFile.setLastModifiedSync(sourceTime);

        final userBinTime = DateTime.now().subtract(const Duration(hours: 1));
        dispatchBin.setLastModifiedSync(userBinTime);
        lockBin.setLastModifiedSync(userBinTime);
        unlockBin.setLastModifiedSync(userBinTime);

        // System unlock is older than user binary
        final sysTime = DateTime.now().subtract(const Duration(hours: 3));
        systemUnlock.setLastModifiedSync(sysTime);

        final customUpkeeper = GhVaultUpkeeper(
          homeDirOverride: tempDir.path,
          packageDirOverride: fakePkg.path,
          systemUnlockBinOverride: systemUnlock.path,
          rootVaultFileOverride: vaultFile.path,
          processRunner: (exec, args) async =>
              ProcessResult(0, 0, 'github_pat_valid', ''),
        );

        final status = await customUpkeeper.check();
        check(status.state).equals(UpkeepState.outdated);
        check(
          status.details.any(
            (d) =>
                d.contains('System unlock binary at') &&
                d.contains('is older than user binary'),
          ),
        ).isTrue();
      },
    );
  });
}
