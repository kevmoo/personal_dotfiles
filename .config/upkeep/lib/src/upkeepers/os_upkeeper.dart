import 'dart:io';

import '../models.dart';
import 'upkeeper.dart';

abstract class OsStrategy {
  Future<bool> isSupported();
  Future<UpkeepStatus> check(String upkeeperId, String displayName);
  Future<UpkeepResult> update(
    String upkeeperId,
    String displayName, {
    bool verbose = false,
  });
}

class GlinuxOsStrategy implements OsStrategy {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  _processRunner;

  GlinuxOsStrategy({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    processRunner,
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
  Future<bool> isSupported() async {
    if (Platform.isMacOS) return false;
    if (Platform.isLinux) {
      if (Directory('/google/src').existsSync() ||
          File('/etc/glinux-release').existsSync()) {
        return true;
      }
      return await _hasCommand('gcertstatus');
    }
    return false;
  }

  @override
  Future<UpkeepStatus> check(String upkeeperId, String displayName) async {
    final issues = <String>[];
    final details = <String>[];
    var state = UpkeepState.upToDate;

    // 1. Check gCert status
    try {
      final gcertResult = await _runProcess('gcertstatus', []);
      final stdout = gcertResult.stdout.toString();
      final match = RegExp(r'expires in (?:(\d+)h)?\s*(?:(\d+)m)?')
          .firstMatch(stdout);

      if (match != null) {
        final hoursStr = match.group(1);
        final hours = hoursStr != null ? int.tryParse(hoursStr) ?? 0 : 0;
        if (hours < 4 && !stdout.contains('expires in 0h 0m')) {
          state = UpkeepState.outdated;
          issues.add('gCert ticket expiring soon (${hours}h remaining)');
          details.add(stdout.trim());
        } else {
          details.add(
            'gCert status: ${stdout.trim().split("\n").firstWhere((l) => l.contains('expires in'), orElse: () => 'OK')}',
          );
        }
      } else if (gcertResult.exitCode != 0) {
        state = UpkeepState.outdated;
        issues.add('gCert ticket inactive or expired');
        details.add(
          'gCert status check failed (exit code ${gcertResult.exitCode}): run gcert',
        );
      }
    } catch (_) {
      // gcertstatus executable missing or error
    }

    // 2. Check pending reboot status
    final hasRebootRequired =
        File('/var/run/reboot-required').existsSync() ||
        File('/run/reboot-required').existsSync();
    if (hasRebootRequired) {
      state = UpkeepState.outdated;
      issues.add('System reboot required');
      details.add('Reboot flag active (/var/run/reboot-required)');
    }

    // 3. Check APT package upgrades
    try {
      final aptResult = await _runProcess('apt-get', ['-s', 'upgrade']);
      if (aptResult.exitCode == 0) {
        final stdout = aptResult.stdout.toString();
        final match = RegExp(r'(\d+)\s+upgraded,\s+(\d+)\s+newly installed')
            .firstMatch(stdout);
        if (match != null) {
          final count = int.tryParse(match.group(1) ?? '0') ?? 0;
          if (count > 0) {
            state = UpkeepState.outdated;
            issues.add('$count APT package update(s) available');
            final lines = stdout.split('\n');
            final upgradedPackages = <String>[];
            bool inUpgradedSection = false;
            for (final line in lines) {
              if (line.contains('The following packages will be upgraded:')) {
                inUpgradedSection = true;
                continue;
              }
              if (inUpgradedSection) {
                if (line.trim().isEmpty ||
                    line.startsWith('The following') ||
                    line.contains('upgraded,')) {
                  break;
                }
                upgradedPackages.addAll(
                  line.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty),
                );
              }
            }
            if (upgradedPackages.isNotEmpty) {
              details.add(
                'APT updates: ${upgradedPackages.take(5).join(', ')}${upgradedPackages.length > 5 ? ' (+${upgradedPackages.length - 5} more)' : ''}',
              );
            } else {
              details.add('APT updates: $count package(s) ready to upgrade');
            }
          }
        }
      }
    } catch (_) {
      // apt-get not available or error
    }

    if (state == UpkeepState.upToDate) {
      return UpkeepStatus(
        upkeeperId: upkeeperId,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'gLinux Cloudtop system is up to date & gCert active',
        details: details,
      );
    } else {
      return UpkeepStatus(
        upkeeperId: upkeeperId,
        displayName: displayName,
        state: state,
        summary: issues.join('; '),
        details: details,
      );
    }
  }

  @override
  Future<UpkeepResult> update(
    String upkeeperId,
    String displayName, {
    bool verbose = false,
  }) async {
    try {
      final gcertResult = await _runProcess('gcert', []);
      if (gcertResult.exitCode == 0) {
        return UpkeepResult(
          upkeeperId: upkeeperId,
          displayName: displayName,
          success: true,
          message: 'gCert refreshed successfully',
        );
      } else {
        return UpkeepResult(
          upkeeperId: upkeeperId,
          displayName: displayName,
          success: false,
          message: 'gCert refresh failed (exit code ${gcertResult.exitCode})',
          errorMessage: gcertResult.stderr.toString(),
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: upkeeperId,
        displayName: displayName,
        success: false,
        message: 'Exception executing gcert refresh',
        errorMessage: e.toString(),
      );
    }
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

class OstreeOsStrategy implements OsStrategy {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  _processRunner;

  OstreeOsStrategy({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    processRunner,
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
  Future<bool> isSupported() async {
    if (Platform.isMacOS) return false;
    if (Platform.isLinux) {
      try {
        final result = await _runProcess('which', ['ujust']);
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  @override
  Future<UpkeepStatus> check(String upkeeperId, String displayName) async {
    try {
      final hasRpmOstree = await _hasCommand('rpm-ostree');
      if (hasRpmOstree) {
        final result = await _runProcess('rpm-ostree', ['upgrade', '--check']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          if (output.contains('No updates available')) {
            return UpkeepStatus(
              upkeeperId: upkeeperId,
              displayName: displayName,
              state: UpkeepState.upToDate,
              summary: 'OS system is up to date',
            );
          } else {
            return UpkeepStatus(
              upkeeperId: upkeeperId,
              displayName: displayName,
              state: UpkeepState.outdated,
              summary: 'OS system updates available (rpm-ostree)',
              details: [output.trim()],
            );
          }
        }
      }

      final hasUjust = await _hasCommand('ujust');
      if (hasUjust) {
        final statusResult = await _runProcess('rpm-ostree', ['status']);
        if (statusResult.exitCode == 0 &&
            statusResult.stdout.toString().contains('staged')) {
          return UpkeepStatus(
            upkeeperId: upkeeperId,
            displayName: displayName,
            state: UpkeepState.outdated,
            summary: 'OS system updates staged (reboot required)',
          );
        }

        return UpkeepStatus(
          upkeeperId: upkeeperId,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'OS system is up to date (no staged updates)',
        );
      }

      return UpkeepStatus(
        upkeeperId: upkeeperId,
        displayName: displayName,
        state: UpkeepState.skipped,
        summary: 'No recognized OS updater found',
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: upkeeperId,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking OS updater',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update(
    String upkeeperId,
    String displayName, {
    bool verbose = false,
  }) async {
    try {
      final proc = await _runProcess('ujust', ['update']);
      if (proc.exitCode == 0) {
        return UpkeepResult(
          upkeeperId: upkeeperId,
          displayName: displayName,
          success: true,
          message: 'ujust update completed successfully',
        );
      } else {
        return UpkeepResult(
          upkeeperId: upkeeperId,
          displayName: displayName,
          success: false,
          message: 'ujust update failed with code ${proc.exitCode}',
          errorMessage: proc.stderr.toString(),
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: upkeeperId,
        displayName: displayName,
        success: false,
        message: 'Exception executing ujust update',
        errorMessage: e.toString(),
      );
    }
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

class MacOsStrategy implements OsStrategy {
  @override
  Future<bool> isSupported() async {
    return Platform.isMacOS;
  }

  @override
  Future<UpkeepStatus> check(String upkeeperId, String displayName) async {
    return UpkeepStatus(
      upkeeperId: upkeeperId,
      displayName: displayName,
      state: UpkeepState.skipped,
      summary: 'Skipped on macOS (native OS notifications active)',
    );
  }

  @override
  Future<UpkeepResult> update(
    String upkeeperId,
    String displayName, {
    bool verbose = false,
  }) async {
    return UpkeepResult(
      upkeeperId: upkeeperId,
      displayName: displayName,
      success: true,
      message: 'Skipped on macOS',
    );
  }
}

class OsUpkeeper implements Upkeeper {
  final List<OsStrategy> _strategies;

  OsUpkeeper({List<OsStrategy>? strategies})
    : _strategies =
          strategies ??
          [GlinuxOsStrategy(), OstreeOsStrategy(), MacOsStrategy()];

  @override
  String get id => 'os';

  @override
  String get displayName => 'OS System Updates';

  Future<OsStrategy?> _getActiveStrategy() async {
    for (final strategy in _strategies) {
      if (await strategy.isSupported()) {
        return strategy;
      }
    }
    return null;
  }

  @override
  Future<bool> isSupported() async {
    return (await _getActiveStrategy()) != null;
  }

  @override
  Future<UpkeepStatus> check() async {
    final strategy = await _getActiveStrategy();
    if (strategy == null) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.skipped,
        summary: 'No recognized OS updater found',
      );
    }
    return strategy.check(id, displayName);
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    final strategy = await _getActiveStrategy();
    if (strategy == null) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'No supported OS updater strategy active',
      );
    }
    return strategy.update(id, displayName, verbose: verbose);
  }
}
