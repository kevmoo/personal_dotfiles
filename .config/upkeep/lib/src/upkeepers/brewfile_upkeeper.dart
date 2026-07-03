import 'dart:io';
import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class BrewfileUpkeeper implements Upkeeper {
  @override
  String get id => 'brewfile';

  @override
  String get displayName => 'Homebrew Brewfile Sync';

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

      // Check installed items for missing comparison
      final leavesResult = await Process.run('brew', ['leaves']);
      final installedLeaves = leavesResult.exitCode == 0
          ? leavesResult.stdout
              .toString()
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
          : <String>{};

      final caskListResult = Platform.isMacOS
          ? await Process.run('brew', ['list', '--cask'])
          : null;
      final installedCasks = (caskListResult?.exitCode == 0)
          ? caskListResult!.stdout
              .toString()
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
          : <String>{};

      final missingFormulae =
          expectedFormulae.where((f) => !installedLeaves.contains(f)).toList();
      final missingCasks =
          expectedCasks.where((c) => !installedCasks.contains(c)).toList();

      final List<String> details = [];
      for (final f in missingFormulae) {
        details.add('Missing formula: $f');
      }
      for (final c in missingCasks) {
        details.add('Missing cask: $c');
      }

      final totalMissing = missingFormulae.length + missingCasks.length;

      if (totalMissing == 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Brewfile packages & casks fully synchronized',
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary: '$totalMissing missing from Brewfile',
        details: details,
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception during Brewfile audit',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    Directory? tempDir;
    try {
      final home = _homeDir();
      final sharedBrewfile =
          File(p.join(home, '.config', 'brew', 'Brewfile.shared'));
      final osBrewfile = File(_getOsBrewfilePath());

      tempDir = Directory.systemTemp.createTempSync('brewfile_upkeep_');
      final tempBrewfile = File(p.join(tempDir.path, 'Brewfile'));

      final buffer = StringBuffer();
      if (sharedBrewfile.existsSync()) {
        buffer.writeln(sharedBrewfile.readAsStringSync());
      }
      if (osBrewfile.existsSync()) {
        buffer.writeln(osBrewfile.readAsStringSync());
      }
      tempBrewfile.writeAsStringSync(buffer.toString());

      final bundleArgs = [
        'bundle',
        '--file=${tempBrewfile.path}',
      ];
      final bundleProc = await Process.run('brew', bundleArgs);
      if (bundleProc.exitCode != 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'brew bundle failed with exit code ${bundleProc.exitCode}',
          errorMessage: bundleProc.stderr.toString(),
        );
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message:
            'Brewfile packages & casks successfully installed and synchronized',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Brewfile sync exception',
        errorMessage: e.toString(),
      );
    } finally {
      if (tempDir != null && tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }
}
