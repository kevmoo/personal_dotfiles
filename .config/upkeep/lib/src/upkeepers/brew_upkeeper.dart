import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class BrewUpkeeper implements Upkeeper {
  @override
  String get id => 'brew';

  @override
  String get displayName => 'Homebrew Package Upgrades';

  @override
  Future<bool> isSupported() async {
    try {
      final result = await Process.run('which', ['brew']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _homeDir() => Platform.environment['HOME'] ?? Directory.current.path;

  String _getOsBrewfilePath() {
    final home = _homeDir();
    if (Platform.isMacOS) {
      return p.join(home, '.config', 'brew', 'Brewfile.mac');
    } else {
      return p.join(home, '.config', 'brew', 'Brewfile.linux');
    }
  }

  Set<String> _parseBrewfileEntries(String filePath, String prefix) {
    final file = File(filePath);
    if (!file.existsSync()) return {};
    final lines = file.readAsLinesSync();
    final set = <String>{};
    final regExp = RegExp('^${RegExp.escape(prefix)}\\s+"([^"]+)"');
    for (final line in lines) {
      final match = regExp.firstMatch(line.trim());
      if (match != null) {
        set.add(match.group(1)!);
      }
    }
    return set;
  }

  bool _isDirectlyInBrewfile(String name, Set<String> expected) {
    if (expected.contains(name)) return true;
    for (final exp in expected) {
      if (exp == name || exp.endsWith('/$name') || name.endsWith('/$exp')) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final home = _homeDir();
      final sharedBrewfile = p.join(home, '.config', 'brew', 'Brewfile.shared');
      final osBrewfile = _getOsBrewfilePath();

      final expectedFormulae = {
        ..._parseBrewfileEntries(sharedBrewfile, 'brew'),
        ..._parseBrewfileEntries(osBrewfile, 'brew'),
      };
      final expectedCasks = {
        ..._parseBrewfileEntries(sharedBrewfile, 'cask'),
        ..._parseBrewfileEntries(osBrewfile, 'cask'),
      };

      // Check outdated via brew outdated --json
      final outdatedResult = await Process.run('brew', ['outdated', '--json']);
      final directOutdatedDetails = <String>[];
      final dependencyOutdatedDetails = <String>[];
      int directOutdatedCount = 0;
      int dependencyOutdatedCount = 0;

      if (outdatedResult.exitCode == 0 &&
          outdatedResult.stdout.toString().trim().isNotEmpty) {
        try {
          final dynamic parsed = jsonDecode(outdatedResult.stdout.toString());
          if (parsed is Map<String, dynamic>) {
            final formulae = parsed['formulae'] as List? ?? [];
            final casks = parsed['casks'] as List? ?? [];

            for (final f in formulae) {
              final name = f['name'] ?? 'unknown';
              final current =
                  (f['installed_versions'] as List?)?.first ?? 'curr';
              final latest = f['current_version'] ?? 'latest';

              if (_isDirectlyInBrewfile(name, expectedFormulae)) {
                directOutdatedCount++;
                directOutdatedDetails.add(
                  'Outdated Brewfile formula: $name ($current -> $latest)',
                );
              } else {
                dependencyOutdatedCount++;
                dependencyOutdatedDetails.add(
                  'Outdated dependency formula: $name ($current -> $latest)',
                );
              }
            }

            for (final c in casks) {
              final name = c['name'] ?? 'unknown';
              final current = c['installed_version'] ?? 'curr';
              final latest = c['current_version'] ?? 'latest';

              if (_isDirectlyInBrewfile(name, expectedCasks)) {
                directOutdatedCount++;
                directOutdatedDetails.add(
                  'Outdated Brewfile cask: $name ($current -> $latest)',
                );
              } else {
                dependencyOutdatedCount++;
                dependencyOutdatedDetails.add(
                  'Outdated dependency cask: $name ($current -> $latest)',
                );
              }
            }
          }
        } catch (_) {}
      }

      final List<String> details = [
        ...directOutdatedDetails,
        ...dependencyOutdatedDetails,
      ];

      final totalOutdated = directOutdatedCount + dependencyOutdatedCount;

      if (totalOutdated == 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'All installed Homebrew packages & casks up to date',
        );
      }

      final summaryParts = <String>[];
      if (directOutdatedCount > 0) {
        summaryParts.add('$directOutdatedCount Brewfile outdated');
      }
      if (dependencyOutdatedCount > 0) {
        summaryParts.add('$dependencyOutdatedCount dependencies outdated');
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary: summaryParts.join(', '),
        details: details,
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception during brew audit',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      // 1. brew update
      final updateProc = await Process.run('brew', ['update']);
      if (updateProc.exitCode != 0 && verbose) {
        stderr.writeln('brew update warning: ${updateProc.stderr}');
      }

      // 2. brew upgrade
      final upgradeProc = await Process.run('brew', ['upgrade']);
      if (upgradeProc.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'brew upgrade failed with exit code ${upgradeProc.exitCode}',
          errorMessage: upgradeProc.stderr.toString(),
        );
      }

      // 3. brew cleanup
      await Process.run('brew', ['cleanup']);

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'Installed Homebrew packages successfully upgraded',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Homebrew package upgrade exception',
        errorMessage: e.toString(),
      );
    }
  }
}
