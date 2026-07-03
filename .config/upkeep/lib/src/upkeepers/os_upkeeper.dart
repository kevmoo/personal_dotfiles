import 'dart:io';

import '../models.dart';
import 'upkeeper.dart';

class OsUpkeeper implements Upkeeper {
  @override
  String get id => 'os';

  @override
  String get displayName => 'OS System Updates (ujust/Linux)';

  @override
  Future<bool> isSupported() async {
    // macOS system updates are explicitly skipped as macOS native notifications handle them
    if (Platform.isMacOS) return false;

    if (Platform.isLinux) {
      try {
        final result = await Process.run('which', ['ujust']);
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  @override
  Future<UpkeepStatus> check() async {
    if (Platform.isMacOS) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.skipped,
        summary: 'Skipped on macOS (native OS notifications active)',
      );
    }

    try {
      // Check if rpm-ostree exists (standard on Bluefin / ostree systems)
      final hasRpmOstree = await _hasCommand('rpm-ostree');
      if (hasRpmOstree) {
        final result = await Process.run('rpm-ostree', ['upgrade', '--check']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          if (output.contains('No updates available')) {
            return UpkeepStatus(
              upkeeperId: id,
              displayName: displayName,
              state: UpkeepState.upToDate,
              summary: 'OS system is up to date',
            );
          } else {
            return UpkeepStatus(
              upkeeperId: id,
              displayName: displayName,
              state: UpkeepState.outdated,
              summary: 'OS system updates available (rpm-ostree)',
              details: [output.trim()],
            );
          }
        }
      }

      // Fallback: check if ujust exists
      final hasUjust = await _hasCommand('ujust');
      if (hasUjust) {
        // If we can't check rpm-ostree directly but ujust is there,
        // we can check if there's a staged deployment in `rpm-ostree status`.
        final statusResult = await Process.run('rpm-ostree', ['status']);
        if (statusResult.exitCode == 0 &&
            statusResult.stdout.toString().contains('staged')) {
          return UpkeepStatus(
            upkeeperId: id,
            displayName: displayName,
            state: UpkeepState.outdated,
            summary: 'OS system updates staged (reboot required)',
          );
        }

        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'OS system is up to date (no staged updates)',
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.skipped,
        summary: 'No recognized OS updater found',
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking OS updater',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    if (Platform.isMacOS) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'Skipped on macOS',
      );
    }

    try {
      final proc = await Process.run('ujust', ['update']);
      if (proc.exitCode == 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message: 'ujust update completed successfully',
        );
      } else {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'ujust update failed with code ${proc.exitCode}',
          errorMessage: proc.stderr.toString(),
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Exception executing ujust update',
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> _hasCommand(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
