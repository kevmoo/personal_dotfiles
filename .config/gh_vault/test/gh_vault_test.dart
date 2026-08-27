import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:gh_vault/gh_vault.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gh_vault_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AdminLease', () {
    test('write and read active lease', () {
      final token = 'ghp_secret_test_token_12345';
      AdminLease.write(
        token: token,
        duration: const Duration(minutes: 5),
        customBaseDir: tempDir.path,
      );

      final lease = AdminLease.readActive(customBaseDir: tempDir.path);
      check(lease).isNotNull();
      check(lease!.token).equals(token);
      check(lease.isExpired).isFalse();
      check(lease.remainingTime.inSeconds).isGreaterThan(250);
    });

    test('expired lease returns null and auto-deletes file', () {
      final file = VaultPaths.leaseFile(customBaseDir: tempDir.path);
      final pastEpochMs = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;

      file.writeAsStringSync(
        jsonEncode({'token': 'expired_token', 'expiresAtEpochMs': pastEpochMs}),
      );

      check(file.existsSync()).isTrue();

      final lease = AdminLease.readActive(customBaseDir: tempDir.path);
      check(lease).isNull();
      check(file.existsSync()).isFalse();
    });

    test('malformed lease returns null and auto-deletes file', () {
      final file = VaultPaths.leaseFile(customBaseDir: tempDir.path);
      file.writeAsStringSync('{invalid json');

      check(file.existsSync()).isTrue();

      final lease = AdminLease.readActive(customBaseDir: tempDir.path);
      check(lease).isNull();
      check(file.existsSync()).isFalse();
    });

    test('revoke deletes active lease', () {
      AdminLease.write(
        token: 'test_token',
        duration: const Duration(minutes: 10),
        customBaseDir: tempDir.path,
      );

      final file = VaultPaths.leaseFile(customBaseDir: tempDir.path);
      check(file.existsSync()).isTrue();

      final revoked = AdminLease.revoke(customBaseDir: tempDir.path);
      check(revoked).isTrue();
      check(file.existsSync()).isFalse();

      final secondRevoke = AdminLease.revoke(customBaseDir: tempDir.path);
      check(secondRevoke).isFalse();
    });
  });

  group('VaultPaths', () {
    test(
      'resolveRealGhExecutable finds binary in search paths and excludes self',
      () {
        final binDir = Directory(p.join(tempDir.path, 'bin'))..createSync();
        final mockGh = File(p.join(binDir.path, 'gh'))
          ..writeAsStringSync('#!/bin/sh\necho gh\n');
        Process.runSync('chmod', ['+x', mockGh.path]);

        final selfBinary = p.join(tempDir.path, 'self', 'gh');

        final resolved = VaultPaths.resolveRealGhExecutable(
          currentExecutable: selfBinary,
          searchPaths: [binDir.path],
        );

        check(resolved).equals(mockGh.path);
      },
    );

    test('resolveRealGhExecutable ignores broken symlinks in search paths', () {
      final binDir = Directory(p.join(tempDir.path, 'bin'))..createSync();
      Link(p.join(binDir.path, 'gh')).createSync('/nonexistent/path/to/gh');

      final resolved = VaultPaths.resolveRealGhExecutable(
        currentExecutable: p.join(tempDir.path, 'self', 'gh'),
        searchPaths: [binDir.path],
      );

      check(resolved).isNull();
    });
  });
}
