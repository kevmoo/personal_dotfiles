import 'dart:convert';
import 'dart:io';

import 'paths.dart';

/// Represents an active, time-bounded admin token lease.
class AdminLease {
  final String token;
  final int expiresAtEpochMs;

  AdminLease({required this.token, required this.expiresAtEpochMs});

  /// The expiration timestamp in UTC.
  DateTime get expiresAt =>
      DateTime.fromMillisecondsSinceEpoch(expiresAtEpochMs, isUtc: true);

  /// Remaining duration before expiration.
  Duration get remainingTime => expiresAt.difference(DateTime.now().toUtc());

  /// True if the current UTC time has passed the expiration timestamp.
  bool get isExpired =>
      DateTime.now().toUtc().millisecondsSinceEpoch >= expiresAtEpochMs;

  /// Reads and validates the active lease from disk. Returns null if missing or
  /// expired.
  static AdminLease? readActive({String? customBaseDir}) {
    final file = VaultPaths.leaseFile(customBaseDir: customBaseDir);
    if (!file.existsSync()) return null;

    try {
      final content =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final lease = AdminLease(
        token: content['token'] as String,
        expiresAtEpochMs: content['expiresAtEpochMs'] as int,
      );

      if (lease.isExpired) {
        try {
          file.deleteSync();
        } catch (_) {}
        return null;
      }

      return lease;
    } catch (_) {
      try {
        file.deleteSync();
      } catch (_) {}
      return null;
    }
  }

  /// Atomically writes an admin lease file with strict permissions (0600).
  static void write({
    required String token,
    required Duration duration,
    int? targetUid,
    String? customBaseDir,
  }) {
    final file = VaultPaths.leaseFile(
      targetUid: targetUid,
      customBaseDir: customBaseDir,
    );
    final tmpFile = File('${file.path}.tmp');
    final expiresAtEpochMs =
        DateTime.now().toUtc().millisecondsSinceEpoch + duration.inMilliseconds;

    final payload = jsonEncode({
      'token': token,
      'expiresAtEpochMs': expiresAtEpochMs,
    });

    tmpFile.writeAsStringSync(payload, flush: true);
    Process.runSync('chmod', ['0600', tmpFile.path]);

    if (targetUid != null) {
      Process.runSync('chown', ['$targetUid', tmpFile.path]);
    }

    tmpFile.renameSync(file.path);
  }

  /// Revokes and deletes any active lease file.
  static bool revoke({String? customBaseDir}) {
    final file = VaultPaths.leaseFile(customBaseDir: customBaseDir);
    if (file.existsSync()) {
      try {
        file.deleteSync();
        return true;
      } on FileSystemException catch (e) {
        stderr.writeln(
          '❌ Failed to revoke lease at ${file.path}: ${e.message}',
        );
        return false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
