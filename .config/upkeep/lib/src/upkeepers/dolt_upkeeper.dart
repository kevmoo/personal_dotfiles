import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class DoltUpkeeper implements Upkeeper {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  _processRunner;

  final String? doltPathOverride;
  final bool? isCloudtopOverride;

  DoltUpkeeper({
    this._processRunner,
    this.doltPathOverride,
    this.isCloudtopOverride,
  });

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) async {
    final runner = _processRunner;
    if (runner != null) {
      return runner(executable, arguments);
    }
    return Process.run(executable, arguments);
  }

  @override
  String get id => 'dolt';

  @override
  String get displayName => 'Dolt Go Binary';

  String _homeDir() => Platform.environment['HOME'] ?? Directory.current.path;

  String _doltPath() =>
      doltPathOverride ?? p.join(_homeDir(), 'go', 'bin', 'dolt');

  bool _isCloudtop() {
    if (isCloudtopOverride != null) return isCloudtopOverride!;
    return Platform.isLinux &&
        (Directory('/google/src').existsSync() ||
            File('/etc/glinux-release').existsSync());
  }

  @override
  Future<bool> isSupported() async {
    // On systems with Homebrew (macOS / Bluefin), brew upkeepers manage dolt,
    // unless on cloudtop where we skip Homebrew and manage it via Go.
    final hasBrew = await _hasCommand('brew');
    if (hasBrew && !_isCloudtop()) return false;

    final doltExists = File(_doltPath()).existsSync();
    return doltExists || (_isCloudtop() && await _hasCommand('go'));
  }

  @override
  Future<UpkeepStatus> check() async {
    final doltFile = File(_doltPath());

    if (!doltFile.existsSync()) {
      if (_isCloudtop()) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Dolt binary not installed (run update to install via go)',
          details: ['Dolt: missing binary at ${_doltPath()}'],
        );
      }
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'Dolt binary not installed (not required on this host)',
      );
    }

    final ({String? outdatedItem, String detail}) finding;
    try {
      final result = await _runProcess(_doltPath(), ['version']);
      final output = result.stdout.toString() + result.stderr.toString();
      finding = _doltVersionFinding(output);
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'Dolt: Error running version check ($e)',
      );
    }

    final outdatedItem = finding.outdatedItem;
    if (outdatedItem != null) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary: outdatedItem,
        details: [finding.detail],
      );
    }

    return UpkeepStatus(
      upkeeperId: id,
      displayName: displayName,
      state: UpkeepState.upToDate,
      summary: 'Dolt binary is up to date',
      details: [finding.detail],
    );
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    if (!File(_doltPath()).existsSync() && !_isCloudtop()) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'Dolt not installed on this host; nothing to do',
      );
    }

    var res = await _runProcess('go', [
      'install',
      'github.com/dolthub/dolt/go/cmd/dolt@latest',
    ]);
    if (res.exitCode != 0) {
      res = await _runProcess('bash', [
        '-c',
        'mkdir -p "\$(dirname ${_doltPath()})" && curl -sL https://github.com/dolthub/dolt/releases/latest/download/dolt-linux-amd64.tar.gz | tar -xz -C /tmp && install -m 755 /tmp/dolt-linux-amd64/bin/dolt ${_doltPath()} && rm -rf /tmp/dolt-linux-amd64',
      ]);
    }
    if (res.exitCode != 0) {
      final error = 'Dolt upgrade failed: ${res.stderr}';
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Failed to upgrade: $error',
        errorMessage: error,
      );
    }

    return UpkeepResult(
      upkeeperId: id,
      displayName: displayName,
      success: true,
      message: 'Upgraded Dolt successfully',
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

/// Classifies `dolt version` output (stdout+stderr combined) into an optional
/// outdated marker and a detail line.
({String? outdatedItem, String detail}) _doltVersionFinding(String output) {
  if (output.contains('Warning: you are on an old version of Dolt')) {
    final match = RegExp(r'The newest version is ([^\s.]+[\.\d]+)')
        .firstMatch(output);
    final newest = match != null ? match.group(1) : 'newer version';
    return (
      outdatedItem: 'Dolt update available -> $newest',
      detail: 'Dolt: ${output.trim()}',
    );
  }
  return (
    outdatedItem: null,
    detail: 'Dolt: ${output.trim().split('\n').first} (up to date)',
  );
}
