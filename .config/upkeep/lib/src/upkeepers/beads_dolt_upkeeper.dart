import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class BeadsDoltUpkeeper implements Upkeeper {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  _processRunner;

  final String? doltPathOverride;
  final String? bdPathOverride;
  final bool? isCloudtopOverride;

  BeadsDoltUpkeeper({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    processRunner,
    this.doltPathOverride,
    this.bdPathOverride,
    this.isCloudtopOverride,
  }) : _processRunner = processRunner;

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) async {
    if (_processRunner != null) {
      return _processRunner!(executable, arguments);
    }
    return Process.run(executable, arguments);
  }

  @override
  String get id => 'beads';

  @override
  String get displayName => 'Beads & Dolt Go Binaries';

  String _homeDir() => Platform.environment['HOME'] ?? Directory.current.path;

  String _doltPath() =>
      doltPathOverride ?? p.join(_homeDir(), 'go', 'bin', 'dolt');
  String _bdPath() => bdPathOverride ?? p.join(_homeDir(), 'go', 'bin', 'bd');

  bool _isCloudtop() {
    if (isCloudtopOverride != null) return isCloudtopOverride!;
    return Platform.isLinux &&
        (Directory('/google/src').existsSync() ||
            File('/etc/glinux-release').existsSync());
  }

  @override
  Future<bool> isSupported() async {
    // On systems with Homebrew (macOS / Bluefin), brew upkeepers manage dolt & beads,
    // unless on cloudtop where we skip Homebrew and manage them via Go.
    final hasBrew = await _hasCommand('brew');
    if (hasBrew && !_isCloudtop()) return false;

    final doltExists = File(_doltPath()).existsSync();
    final bdExists = File(_bdPath()).existsSync();
    return doltExists || bdExists || (_isCloudtop() && await _hasCommand('go'));
  }

  @override
  Future<UpkeepStatus> check() async {
    final details = <String>[];
    final outdatedItems = <String>[];
    var isOutdated = false;

    final doltFile = File(_doltPath());
    final bdFile = File(_bdPath());

    if (!doltFile.existsSync() && !bdFile.existsSync()) {
      if (_isCloudtop()) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Beads and Dolt binaries not installed (run update to install via go)',
        );
      }
    }

    // 1. Audit Dolt
    if (doltFile.existsSync()) {
      try {
        final result = await _runProcess(_doltPath(), ['version']);
        final output = result.stdout.toString() + result.stderr.toString();
        if (output.contains('Warning: you are on an old version of Dolt')) {
          isOutdated = true;
          final match = RegExp(r'The newest version is ([^\s.]+[\.\d]+)')
              .firstMatch(output);
          final newest = match != null ? match.group(1) : 'newer version';
          outdatedItems.add('Dolt update available -> $newest');
          details.add('Dolt: ${output.trim()}');
        } else {
          final firstLine = output.trim().split('\n').first;
          details.add('Dolt: $firstLine (up to date)');
        }
      } catch (e) {
        details.add('Dolt: Error running version check ($e)');
      }
    } else if (_isCloudtop()) {
      isOutdated = true;
      outdatedItems.add('Dolt binary not installed -> install via go');
      details.add('Dolt: missing binary at ${_doltPath()}');
    }

    // 2. Audit Beads (bd)
    if (bdFile.existsSync()) {
      try {
        final result = await _runProcess(_bdPath(), ['--version']);
        final stdout = result.stdout.toString().trim();
        details.add('Beads (bd): $stdout');
      } catch (e) {
        details.add('Beads (bd): Error checking version ($e)');
      }
    } else if (_isCloudtop()) {
      isOutdated = true;
      outdatedItems.add('Beads (bd) binary not installed -> install via go');
      details.add('Beads (bd): missing binary at ${_bdPath()}');
    }

    if (isOutdated) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary: outdatedItems.join('; '),
        details: details,
      );
    }

    return UpkeepStatus(
      upkeeperId: id,
      displayName: displayName,
      state: UpkeepState.upToDate,
      summary: 'Beads & Dolt binaries are up to date',
      details: details,
    );
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    final updated = <String>[];
    final errors = <String>[];

    // Update Dolt if installed or on cloudtop
    if (File(_doltPath()).existsSync() || _isCloudtop()) {
      var res = await _runProcess('go', [
        'install',
        'github.com/dolthub/dolt/go/cmd/dolt@latest',
      ]);
      if (res.exitCode != 0) {
        res = await _runProcess('bash', [
          '-c',
          'curl -sL https://github.com/dolthub/dolt/releases/latest/download/dolt-linux-amd64.tar.gz | tar -xz -C /tmp && cp /tmp/dolt-linux-amd64/bin/dolt ${_doltPath()} && rm -rf /tmp/dolt-linux-amd64',
        ]);
      }
      if (res.exitCode == 0) {
        updated.add('Dolt');
      } else {
        errors.add('Dolt upgrade failed: ${res.stderr}');
      }
    }

    // Update Beads if installed or on cloudtop
    if (File(_bdPath()).existsSync() || _isCloudtop()) {
      final res = await _runProcess('go', [
        'install',
        'github.com/steveyegge/beads/cmd/bd@latest',
      ]);
      if (res.exitCode == 0) {
        updated.add('Beads (bd)');
      } else {
        errors.add('Beads upgrade failed: ${res.stderr}');
      }
    }

    if (errors.isNotEmpty) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Failed to upgrade: ${errors.join(', ')}',
        errorMessage: errors.join('\n'),
      );
    }

    return UpkeepResult(
      upkeeperId: id,
      displayName: displayName,
      success: true,
      message: 'Upgraded ${updated.join(', ')} successfully',
    );
  }

  Future<bool> _hasCommand(String command) async {
    try {
      final result = await _runProcess('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
