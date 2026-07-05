import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'upkeeper.dart';

class GuacamoleUpkeeper implements Upkeeper {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  _processRunner;

  GuacamoleUpkeeper({
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
  String get id => 'guacamole';

  @override
  String get displayName => 'Apache Guacamole Stack';

  @override
  Future<bool> isSupported() async {
    if (!Platform.isLinux) return false;
    try {
      final res = await _runProcess('which', ['podman']);
      if (res.exitCode != 0) return false;

      // Check if any guac Quadlet container file exists
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return false;
      final guacSvc = File('$home/.config/containers/systemd/guac.pod');
      return guacSvc.existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final res = await _runProcess('podman', [
        'auto-update',
        '--dry-run',
        '--format',
        'json',
      ]);

      if (res.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Failed to run podman auto-update --dry-run',
          errorMessage: res.stderr.toString().trim(),
        );
      }

      final output = res.stdout.toString().trim();
      if (output.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Guacamole stack is up to date',
        );
      }

      final List<dynamic> jsonList;
      try {
        jsonList = jsonDecode(output) as List<dynamic>;
      } catch (e) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Failed to parse podman auto-update output',
          errorMessage: e.toString(),
        );
      }

      final outdatedContainers = <String>[];
      final details = <String>[];

      for (final item in jsonList) {
        if (item is Map<String, dynamic>) {
          final containerName = item['ContainerName'] as String? ?? '';
          final image = item['Image'] as String? ?? '';
          final updated = item['Updated'] as String? ?? '';

          if (containerName.isNotEmpty) {
            if (updated == 'pending' || updated == 'true') {
              outdatedContainers.add(containerName);
              details.add(
                'Container "$containerName" ($image) update is available',
              );
            } else {
              details.add('Container "$containerName" ($image) is up to date');
            }
          }
        }
      }

      if (outdatedContainers.isNotEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Updates available for: ${outdatedContainers.join(', ')}',
          details: details,
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'Guacamole stack is up to date',
        details: details,
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking Guacamole stack updates',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final res = await _runProcess('podman', ['auto-update']);
      if (res.exitCode == 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message:
              'Guacamole stack updated successfully via podman auto-update',
        );
      } else {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message:
              'Failed to update Guacamole stack (exit code ${res.exitCode})',
          errorMessage: res.stderr.toString().trim(),
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Exception updating Guacamole stack',
        errorMessage: e.toString(),
      );
    }
  }
}
