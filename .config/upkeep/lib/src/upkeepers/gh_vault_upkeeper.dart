import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class GhVaultUpkeeper implements Upkeeper {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  processRunner;
  final String? homeDirOverride;
  final String? packageDirOverride;
  final String? systemUnlockBinOverride;
  final String? rootVaultFileOverride;

  GhVaultUpkeeper({
    this.processRunner,
    this.homeDirOverride,
    this.packageDirOverride,
    this.systemUnlockBinOverride,
    this.rootVaultFileOverride,
  });

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) async {
    final runner = processRunner;
    if (runner != null) {
      return runner(executable, arguments);
    }
    return Process.run(executable, arguments);
  }

  @override
  String get id => 'gh_vault';

  @override
  String get displayName => 'GitHub CLI Vault & Agent Safeguards';

  String _homeDir() =>
      homeDirOverride ?? Platform.environment['HOME'] ?? Directory.current.path;

  String get _packageDir =>
      packageDirOverride ?? p.join(_homeDir(), '.config', 'gh_vault');
  String get _dispatchBin => p.join(_homeDir(), '.local', 'bin', 'gh');
  String get _lockBin => p.join(_homeDir(), '.local', 'bin', 'gh-lock');
  String get _userUnlockBin => p.join(_homeDir(), '.local', 'bin', 'gh-unlock');
  String get _systemUnlockBin =>
      systemUnlockBinOverride ?? '/usr/local/bin/gh-unlock';
  String get _rootVaultFile =>
      rootVaultFileOverride ?? '/etc/github/admin.token';

  @override
  Future<bool> isSupported() async {
    return Directory(_packageDir).existsSync();
  }

  DateTime? _latestSourceMtime() {
    final pkgDir = Directory(_packageDir);
    if (!pkgDir.existsSync()) return null;

    DateTime? latest;
    void checkFile(File f) {
      if (f.existsSync()) {
        final mtime = f.lastModifiedSync();
        if (latest == null || mtime.isAfter(latest!)) {
          latest = mtime;
        }
      }
    }

    void scanDir(Directory d) {
      if (!d.existsSync()) return;
      for (final entity in d.listSync(recursive: true)) {
        if (entity is File &&
            (entity.path.endsWith('.dart') ||
                p.basename(entity.path) == 'pubspec.yaml' ||
                p.basename(entity.path) == 'pubspec.lock')) {
          checkFile(entity);
        }
      }
    }

    scanDir(Directory(p.join(_packageDir, 'lib')));
    scanDir(Directory(p.join(_packageDir, 'bin')));
    checkFile(File(p.join(_packageDir, 'pubspec.yaml')));
    checkFile(File(p.join(_packageDir, 'pubspec.lock')));

    return latest;
  }

  @override
  Future<UpkeepStatus> check() async {
    final missing = <String>[];
    final warnings = <String>[];
    final actions = <String>[];

    // 1. Check root vault directory
    final vaultDir = Directory(p.dirname(_rootVaultFile));
    if (!vaultDir.existsSync()) {
      missing.add('Root vault directory missing at ${vaultDir.path}');
      actions.add("Run 'sudo gh-unlock --init' to configure root admin token");
    }

    // 2. Check system unlock executable
    final systemUnlock = File(_systemUnlockBin);
    if (!systemUnlock.existsSync()) {
      missing.add('System unlock binary missing at $_systemUnlockBin');
      actions.add(
        "Run 'sudo install -m 0755 $_userUnlockBin $_systemUnlockBin'",
      );
    }

    // 3. Check user binaries
    final dispatchBin = File(_dispatchBin);
    final lockBin = File(_lockBin);
    final userUnlockBin = File(_userUnlockBin);

    if (!dispatchBin.existsSync()) {
      missing.add('User dispatcher missing at $_dispatchBin');
    }
    if (!lockBin.existsSync()) {
      missing.add('User lock binary missing at $_lockBin');
    }
    if (!userUnlockBin.existsSync()) {
      missing.add('User unlock binary missing at $_userUnlockBin');
    }

    // 4. Check binary freshness against all source Dart/pubspec files
    final latestSource = _latestSourceMtime();
    if (latestSource != null) {
      final staleUserBins = <String>[];
      for (final bin in [dispatchBin, lockBin, userUnlockBin]) {
        if (bin.existsSync() && latestSource.isAfter(bin.lastModifiedSync())) {
          staleUserBins.add(p.basename(bin.path));
        }
      }
      if (staleUserBins.isNotEmpty) {
        warnings.add(
          'User binaries (${staleUserBins.join(', ')}) are older than source Dart package',
        );
        actions.add("Run 'upkeep update gh_vault' to recompile user binaries");
      }

      // Check system unlock binary freshness
      if (systemUnlock.existsSync() &&
          userUnlockBin.existsSync() &&
          userUnlockBin.lastModifiedSync().isAfter(
            systemUnlock.lastModifiedSync(),
          )) {
        warnings.add(
          'System unlock binary at $_systemUnlockBin is older than user binary',
        );
        actions.add(
          "Run 'sudo install -m 0755 $_userUnlockBin $_systemUnlockBin'",
        );
      }
    }

    // 5. Check active gh auth status
    try {
      final authProc = await _runProcess('gh', ['auth', 'status']);
      final output = '${authProc.stdout}\n${authProc.stderr}';
      if (output.contains('gho_')) {
        warnings.add(
          'Baseline gh is using broad OAuth token (gho_). '
          'Recommend logging in with restricted Fine-Grained PAT: '
          'echo "<PAT>" | gh auth login --with-token',
        );
      }
    } catch (_) {
      // gh may not be on PATH yet if not installed
    }

    if (missing.isNotEmpty) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary:
            'GitHub CLI vault is partially configured (${missing.length} missing)',
        details: [...missing, ...warnings, ...actions],
      );
    }

    if (warnings.isNotEmpty) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary: 'GitHub CLI vault active with configuration warnings',
        details: warnings,
      );
    }

    return UpkeepStatus(
      upkeeperId: id,
      displayName: displayName,
      state: UpkeepState.upToDate,
      summary: 'gh_vault configured & baseline Fine-Grained PAT active',
    );
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final localBinDir = Directory(p.join(_homeDir(), '.local', 'bin'));
      if (!localBinDir.existsSync()) {
        localBinDir.createSync(recursive: true);
      }

      // Recompile user binaries
      final dispatchSrc = p.join(_packageDir, 'bin', 'gh_dispatch.dart');
      final lockSrc = p.join(_packageDir, 'bin', 'gh_lock.dart');
      final unlockSrc = p.join(_packageDir, 'bin', 'gh_unlock.dart');

      final compDispatch = await _runProcess('dart', [
        'compile',
        'exe',
        dispatchSrc,
        '-o',
        _dispatchBin,
      ]);

      if (compDispatch.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to compile gh_dispatch.dart',
          errorMessage: compDispatch.stderr.toString(),
        );
      }

      final compLock = await _runProcess('dart', [
        'compile',
        'exe',
        lockSrc,
        '-o',
        _lockBin,
      ]);

      if (compLock.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to compile gh_lock.dart',
          errorMessage: compLock.stderr.toString(),
        );
      }

      final compUnlock = await _runProcess('dart', [
        'compile',
        'exe',
        unlockSrc,
        '-o',
        _userUnlockBin,
      ]);

      if (compUnlock.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to compile gh_unlock.dart',
          errorMessage: compUnlock.stderr.toString(),
        );
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'gh_vault user binaries recompiled successfully',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'gh_vault update failed',
        errorMessage: e.toString(),
      );
    }
  }
}
