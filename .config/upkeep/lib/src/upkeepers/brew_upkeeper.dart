import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class BrewUpkeeper implements Upkeeper {
  final bool? isCloudtopOverride;

  BrewUpkeeper({this.isCloudtopOverride});

  @override
  String get id => 'brew';

  @override
  String get displayName => 'Homebrew Package Upgrades';

  bool _isCloudtop() {
    if (isCloudtopOverride != null) return isCloudtopOverride!;
    return Platform.isLinux &&
        (Directory('/google/src').existsSync() ||
            File('/etc/glinux-release').existsSync());
  }

  @override
  Future<bool> isSupported() async {
    if (_isCloudtop()) return false;
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

  ({List<String> direct, List<String> dependency}) _partitionOutdatedItems(
    List<dynamic> items,
    Set<String> expected, {
    required String kind,
  }) {
    final direct = <String>[];
    final dependency = <String>[];
    for (final raw in items.whereType<Map<String, dynamic>>()) {
      final name = (raw['name'] as String?) ?? 'unknown';
      final installedList = raw['installed_versions'] as List?;
      final current =
          installedList?.firstOrNull ?? raw['installed_version'] ?? 'curr';
      final latest = raw['current_version'] ?? 'latest';
      if (_isDirectlyInBrewfile(name, expected)) {
        direct.add('Outdated Brewfile $kind: $name ($current -> $latest)');
      } else {
        dependency.add(
          'Outdated dependency $kind: $name ($current -> $latest)',
        );
      }
    }
    return (direct: direct, dependency: dependency);
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

      final outdatedResult = await Process.run('brew', ['outdated', '--json']);
      final directOutdatedDetails = <String>[];
      final dependencyOutdatedDetails = <String>[];

      final rawOut = outdatedResult.stdout.toString().trim();
      if (outdatedResult.exitCode == 0 && rawOut.isNotEmpty) {
        try {
          final dynamic parsed = jsonDecode(rawOut);
          if (parsed is Map<String, dynamic>) {
            final formulae = _partitionOutdatedItems(
              parsed['formulae'] as List? ?? const [],
              expectedFormulae,
              kind: 'formula',
            );
            final casks = _partitionOutdatedItems(
              parsed['casks'] as List? ?? const [],
              expectedCasks,
              kind: 'cask',
            );
            directOutdatedDetails
              ..addAll(formulae.direct)
              ..addAll(casks.direct);
            dependencyOutdatedDetails
              ..addAll(formulae.dependency)
              ..addAll(casks.dependency);
          }
        } catch (_) {}
      }

      final details = <String>[
        ...directOutdatedDetails,
        ...dependencyOutdatedDetails,
      ];
      if (details.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'All installed Homebrew packages & casks up to date',
        );
      }

      final summaryParts = <String>[
        if (directOutdatedDetails.isNotEmpty)
          '${directOutdatedDetails.length} Brewfile outdated',
        if (dependencyOutdatedDetails.isNotEmpty)
          '${dependencyOutdatedDetails.length} dependencies outdated',
      ];

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
