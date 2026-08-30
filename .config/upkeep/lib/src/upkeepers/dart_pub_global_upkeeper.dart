import 'dart:io';

import '../models.dart';
import 'upkeeper.dart';

class DartPubGlobalUpkeeper implements Upkeeper {
  final ProcessRunner _processRunner;

  DartPubGlobalUpkeeper({ProcessRunner? processRunner})
    : _processRunner = processRunner ?? Process.run;

  @override
  String get id => 'dart_pub_global';

  @override
  String get displayName => 'Legacy Dart Pub Global Packages';

  @override
  Future<bool> isSupported() async {
    try {
      final res = await _processRunner('dart', ['--version']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final res = await _processRunner('dart', ['pub', 'global', 'list']);
      if (res.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.error,
          summary: 'Failed to list legacy pub global packages',
          errorMessage: res.stderr.toString().trim(),
        );
      }

      final lines = res.stdout
          .toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'No legacy pub global packages found',
        );
      }

      final packageNames = <String>[];
      final manualCommands = <String>[];

      for (final line in lines) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          final pkg = parts.first;
          packageNames.add(pkg);
          manualCommands.add('dart pub global deactivate $pkg');
        }
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary:
            'Found ${packageNames.length} legacy global package(s): ${packageNames.join(', ')}',
        details: [
          'Legacy `dart pub global activate` packages are deprecated in favor of `dart install`.',
          'To deactivate manually, run:',
          ...manualCommands.map((cmd) => '  $cmd'),
        ],
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking legacy global pub packages',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final listRes = await _processRunner('dart', ['pub', 'global', 'list']);
      if (listRes.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to list legacy pub global packages for deactivation',
          errorMessage: listRes.stderr.toString().trim(),
        );
      }

      final lines = listRes.stdout
          .toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message: 'No legacy pub global packages found to deactivate',
        );
      }

      final deactivated = <String>[];
      final errors = <String>[];

      for (final line in lines) {
        final pkg = line.split(RegExp(r'\s+')).first;
        if (pkg.isEmpty) continue;

        final deactRes = await _processRunner('dart', [
          'pub',
          'global',
          'deactivate',
          pkg,
        ]);
        if (deactRes.exitCode == 0) {
          deactivated.add(pkg);
        } else {
          errors.add('$pkg: ${deactRes.stderr.toString().trim()}');
        }
      }

      if (errors.isNotEmpty) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message:
              'Failed to deactivate some global packages: ${errors.join('; ')}',
          errorMessage: errors.join('\n'),
        );
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message:
            'Successfully deactivated ${deactivated.length} legacy global package(s): ${deactivated.join(', ')}',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Exception deactivating legacy global pub packages',
        errorMessage: e.toString(),
      );
    }
  }
}
