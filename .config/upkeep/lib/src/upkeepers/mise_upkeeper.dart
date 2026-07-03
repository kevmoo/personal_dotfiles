import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'upkeeper.dart';

class MiseUpkeeper implements Upkeeper {
  @override
  String get id => 'mise';

  @override
  String get displayName => 'Mise Tool Versions';

  @override
  Future<bool> isSupported() async {
    try {
      final result = await Process.run('which', ['mise']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final result = await Process.run('mise', ['outdated', '--json']);
      if (result.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Failed to check mise status',
          errorMessage: result.stderr.toString().trim(),
        );
      }

      final String output = result.stdout.toString().trim();
      if (output.isEmpty || output == '{}' || output == '[]') {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'All tool versions current',
        );
      }

      final dynamic parsed = jsonDecode(output);
      final List<String> details = [];

      if (parsed is Map<String, dynamic>) {
        parsed.forEach((tool, info) {
          final current = info['current'] ?? info['requested'] ?? 'unknown';
          final latest = info['latest'] ?? 'latest';
          details.add('$tool ($current -> $latest)');
        });
      } else if (parsed is List) {
        for (final item in parsed) {
          if (item is Map<String, dynamic>) {
            final name = item['name'] ?? item['plugin'] ?? 'unknown';
            final current = item['current'] ?? 'unknown';
            final latest = item['latest'] ?? 'latest';
            details.add('$name ($current -> $latest)');
          }
        }
      }

      if (details.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'All tool versions current',
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary: '${details.length} tool version(s) outdated',
        details: details,
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception during mise check',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final process = await Process.start(
        'mise',
        ['upgrade'],
        mode: verbose ? ProcessStartMode.inheritStdio : ProcessStartMode.normal,
      );
      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message: 'Successfully upgraded all mise tool versions',
        );
      } else {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'mise upgrade exited with code $exitCode',
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Failed to run mise upgrade',
        errorMessage: e.toString(),
      );
    }
  }
}
