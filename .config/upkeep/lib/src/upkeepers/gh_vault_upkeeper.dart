import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class GhVaultUpkeeper implements Upkeeper {
  @override
  String get id => 'gh_vault';

  @override
  String get displayName => 'GitHub CLI Vault & Agent Safeguards';

  String _homeDir() => Platform.environment['HOME'] ?? Directory.current.path;

  String get _packageDir => p.join(_homeDir(), '.config', 'gh_vault');
  String get _dispatchBin => p.join(_homeDir(), '.local', 'bin', 'gh');
  String get _lockBin => p.join(_homeDir(), '.local', 'bin', 'gh-lock');
  String get _systemUnlockBin => '/usr/local/bin/gh-unlock';
  String get _rootVaultFile => '/etc/github/admin.token';

  @override
  Future<bool> isSupported() async {
    return Directory(_packageDir).existsSync();
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
        "Run 'sudo install -m 0755 ~/.local/bin/gh-unlock /usr/local/bin/gh-unlock'",
      );
    }

    // 3. Check user binaries
    final dispatchBin = File(_dispatchBin);
    final lockBin = File(_lockBin);

    if (!dispatchBin.existsSync()) {
      missing.add('User dispatcher missing at $_dispatchBin');
    }
    if (!lockBin.existsSync()) {
      missing.add('User lock binary missing at $_lockBin');
    }

    // 4. Check binary freshness against source Dart files
    if (dispatchBin.existsSync()) {
      final dispatchSrc = File(p.join(_packageDir, 'bin', 'gh_dispatch.dart'));
      if (dispatchSrc.existsSync()) {
        final srcMtime = dispatchSrc.lastModifiedSync();
        final binMtime = dispatchBin.lastModifiedSync();
        if (srcMtime.isAfter(binMtime)) {
          warnings.add('User dispatcher is older than source Dart package');
        }
      }
    }

    // 5. Check active gh auth status
    try {
      final authProc = await Process.run('gh', ['auth', 'status']);
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

      final compDispatch = await Process.run('dart', [
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

      final compLock = await Process.run('dart', [
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
