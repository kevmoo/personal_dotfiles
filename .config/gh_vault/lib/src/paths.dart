import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves system, vault, and volatile runtime paths cross-platform.
class VaultPaths {
  static const String defaultVaultFile = '/etc/github/admin.token';

  /// Resolves the volatile runtime directory for storing the active lease.
  static Directory runtimeDir({int? targetUid, String? customBaseDir}) {
    if (customBaseDir != null) {
      final dir = Directory(customBaseDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }

    final uid = targetUid ?? currentUid();

    if (Platform.isLinux) {
      if (targetUid == null || targetUid == currentUid()) {
        final xdg = Platform.environment['XDG_RUNTIME_DIR'];
        if (xdg != null && Directory(xdg).existsSync()) {
          final dir = Directory(p.join(xdg, 'gh_vault'));
          _ensureSecureDir(dir, uid);
          return dir;
        }
      }
      final runUser = Directory('/run/user/$uid');
      if (runUser.existsSync()) {
        final dir = Directory(p.join(runUser.path, 'gh_vault'));
        _ensureSecureDir(dir, uid);
        return dir;
      }
    }

    // macOS & fallback Linux
    final dir = Directory('/private/tmp/.gh_vault_$uid');
    _ensureSecureDir(dir, uid);
    return dir;
  }

  /// Resolves the active lease JSON file path.
  static File leaseFile({int? targetUid, String? customBaseDir}) => File(
    p.join(
      runtimeDir(targetUid: targetUid, customBaseDir: customBaseDir).path,
      'lease.json',
    ),
  );

  /// Resolves current effective UID.
  static int currentUid() {
    final res = Process.runSync('id', ['-u']);
    return int.parse(res.stdout.toString().trim());
  }

  static void _ensureSecureDir(Directory dir, int ownerUid) {
    if (FileSystemEntity.isLinkSync(dir.path)) {
      throw FileSystemException(
        'Security violation: runtime directory is a symlink',
        dir.path,
      );
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      Process.runSync('chmod', ['0700', dir.path]);
      if (Platform.environment['SUDO_USER'] != null) {
        Process.runSync('chown', ['$ownerUid', dir.path]);
      }
    }
  }

  /// Locates the genuine upstream `gh` binary, excluding the dispatcher itself.
  static String? resolveRealGhExecutable({
    String? currentExecutable,
    List<String>? searchPaths,
    List<String>? candidatePaths,
  }) {
    final selfPaths = <String>{
      Platform.resolvedExecutable,
      Platform.script.toFilePath(),
      p.join(Platform.environment['HOME'] ?? '', '.local', 'bin', 'gh'),
      ...?currentExecutable == null ? null : [currentExecutable],
    };

    bool isSelf(File f) {
      if (selfPaths.contains(f.path)) return true;
      try {
        return selfPaths.contains(f.resolveSymbolicLinksSync());
      } on FileSystemException {
        return false;
      }
    }

    // 1. Check PATH environment directories first
    final rawPath = Platform.environment['PATH'] ?? '';
    final dirs = searchPaths ?? rawPath.split(':');
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      final file = File(p.join(dir, 'gh'));
      if (file.existsSync() && !isSelf(file)) {
        return file.path;
      }
    }

    // 2. Fall back to known candidate paths
    if (searchPaths == null || candidatePaths != null) {
      final candidates =
          candidatePaths ??
          ['/opt/homebrew/bin/gh', '/usr/local/bin/gh', '/usr/bin/gh'];

      for (final candidate in candidates) {
        final file = File(candidate);
        if (file.existsSync() && !isSelf(file)) {
          return candidate;
        }
      }
    }

    return null;
  }
}
