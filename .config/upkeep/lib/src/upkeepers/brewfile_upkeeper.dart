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

      final allFormulaeResult = await Process.run('brew', [
        'list',
        '--formula',
      ]);
      final allFormulae = allFormulaeResult.exitCode == 0
          ? allFormulaeResult.stdout
                .toString()
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
          : <String>{};

      final caskListResult = await Process.run('brew', ['list', '--cask']);
      final installedCasks = (caskListResult.exitCode == 0)
          ? caskListResult.stdout
                .toString()
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
          : <String>{};

      final missingFormulae = expectedFormulae.where((f) {
        if (allFormulae.contains(f)) return false;
        if (f.contains('/')) {
          final shortName = f.split('/').last;
          if (allFormulae.contains(shortName)) return false;
        }
        return true;
      }).toList();

      final missingCasks = expectedCasks.where((c) {
        if (installedCasks.contains(c)) return false;
        if (c.contains('/')) {
          final shortName = c.split('/').last;
          if (installedCasks.contains(shortName)) return false;
        }
        return true;
      }).toList();

      final unmanagedFormulae = installedLeaves
          .where((f) => !_matchesExpected(f, expectedFormulae))
          .toList();

      final unmanagedCasks = installedCasks
          .where((c) => !_matchesExpected(c, expectedCasks))
          .toList();

      final List<String> details = [];
      for (final f in missingFormulae) {
        details.add('Missing formula: $f');
      }
      for (final c in missingCasks) {
        details.add('Missing cask: $c');
      }
      for (final f in unmanagedFormulae) {
        details.add('Unmanaged formula: $f');
      }
      for (final c in unmanagedCasks) {
        details.add('Unmanaged cask: $c');
      }

      final totalMissing = missingFormulae.length + missingCasks.length;
      final totalUnmanaged = unmanagedFormulae.length + unmanagedCasks.length;
      final totalDiscrepancies = totalMissing + totalUnmanaged;

      if (totalDiscrepancies == 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Brewfile packages & casks fully synchronized',
        );
      }

      final summaryParts = <String>[];
      if (totalMissing > 0) {
        summaryParts.add('$totalMissing missing from Brewfile');
      }
      if (totalUnmanaged > 0) {
        summaryParts.add('$totalUnmanaged unmanaged in Brewfile');
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
        summary: 'Exception during Brewfile audit',
        errorMessage: e.toString(),
      );
    }
  }

  bool _matchesExpected(String name, Set<String> expected) {
    if (expected.contains(name)) return true;
    for (final exp in expected) {
      if (exp == name || exp.endsWith('/$name') || name.endsWith('/$exp')) {
        return true;
      }
    }
    return false;
  }

  Future<void> triageInteractive() async {
    final home = _homeDir();
    final sharedPath = p.join(home, '.config', 'brew', 'Brewfile.shared');
    final osPath = _getOsBrewfilePath();
    final sharedFile = File(sharedPath);
    final osFile = File(osPath);

    final osLabel = Platform.isMacOS ? 'mac' : 'linux';
    final osKey = Platform.isMacOS ? 'm' : 'l';

    final expectedFormulae = {
      ..._parseBrewfileEntries(sharedPath, 'brew'),
      ..._parseBrewfileEntries(osPath, 'brew'),
    };
    final expectedCasks = {
      ..._parseBrewfileEntries(sharedPath, 'cask'),
      ..._parseBrewfileEntries(osPath, 'cask'),
    };

    final leavesResult = await Process.run('brew', ['leaves']);
    final installedLeaves = leavesResult.exitCode == 0
        ? leavesResult.stdout
              .toString()
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
        : <String>{};

    final caskListResult = await Process.run('brew', ['list', '--cask']);
    final installedCasks = (caskListResult.exitCode == 0)
        ? caskListResult.stdout
              .toString()
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
        : <String>{};

    final unmanagedFormulae = installedLeaves
        .where((f) => !_matchesExpected(f, expectedFormulae))
        .toList();
    final unmanagedCasks = installedCasks
        .where((c) => !_matchesExpected(c, expectedCasks))
        .toList();

    final allFormulaeResult = await Process.run('brew', ['list', '--formula']);
    final allFormulae = allFormulaeResult.exitCode == 0
        ? allFormulaeResult.stdout
              .toString()
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
        : <String>{};

    final missingFormulae = expectedFormulae.where((f) {
      if (allFormulae.contains(f)) return false;
      if (f.contains('/')) {
        final shortName = f.split('/').last;
        if (allFormulae.contains(shortName)) return false;
      }
      return true;
    }).toList();

    final missingCasks = expectedCasks.where((c) {
      if (installedCasks.contains(c)) return false;
      if (c.contains('/')) {
        final shortName = c.split('/').last;
        if (installedCasks.contains(shortName)) return false;
      }
      return true;
    }).toList();

    if (unmanagedFormulae.isEmpty &&
        unmanagedCasks.isEmpty &&
        missingFormulae.isEmpty &&
        missingCasks.isEmpty) {
      print('✨ All Homebrew packages are fully synchronized with Brewfiles!');
      return;
    }

    print('\n🍏 Interactive Brewfile Triage\n');

    if (unmanagedFormulae.isNotEmpty) {
      print('📦 Managing unmanaged Formulae:');
      for (final f in unmanagedFormulae) {
        while (true) {
          stdout.write(
            "Add formula '$f' to Brewfile? [s]hared, [$osKey]$osLabel, or [n]o: ",
          );
          final choice = stdin.readLineSync()?.trim().toLowerCase() ?? '';
          if (choice == 's') {
            sharedFile.writeAsStringSync('brew "$f"\n', mode: FileMode.append);
            print("Added '$f' to Brewfile.shared");
            break;
          } else if (choice == osKey) {
            osFile.writeAsStringSync('brew "$f"\n', mode: FileMode.append);
            print("Added '$f' to Brewfile.$osLabel");
            break;
          } else if (choice == 'n' || choice.isEmpty) {
            print("Skipped '$f'");
            break;
          }
        }
      }
      print('');
    }

    if (unmanagedCasks.isNotEmpty) {
      print('🖥️ Managing unmanaged Casks:');
      for (final c in unmanagedCasks) {
        while (true) {
          stdout.write(
            "Add cask '$c' to Brewfile? [s]hared, [$osKey]$osLabel, or [n]o: ",
          );
          final choice = stdin.readLineSync()?.trim().toLowerCase() ?? '';
          if (choice == 's') {
            sharedFile.writeAsStringSync('cask "$c"\n', mode: FileMode.append);
            print("Added '$c' to Brewfile.shared");
            break;
          } else if (choice == osKey) {
            osFile.writeAsStringSync('cask "$c"\n', mode: FileMode.append);
            print("Added '$c' to Brewfile.$osLabel");
            break;
          } else if (choice == 'n' || choice.isEmpty) {
            print("Skipped '$c'");
            break;
          }
        }
      }
      print('');
    }

    if (missingFormulae.isNotEmpty) {
      print('⚠️ Managing missing Formulae (in Brewfile but not installed):');
      for (final f in missingFormulae) {
        while (true) {
          stdout.write(
            "Action for formula '$f'? [i]nstall, [r]emove from config, or [k]eep: ",
          );
          final choice = stdin.readLineSync()?.trim().toLowerCase() ?? '';
          if (choice == 'i') {
            print('Running: brew install $f');
            await Process.run('brew', ['install', f]);
            break;
          } else if (choice == 'r') {
            _removeFromBrewfile(sharedFile, 'brew "$f"');
            _removeFromBrewfile(osFile, 'brew "$f"');
            print("Removed '$f' from Brewfile");
            break;
          } else if (choice == 'k' || choice.isEmpty) {
            print("Kept configuration for '$f'");
            break;
          }
        }
      }
      print('');
    }

    if (missingCasks.isNotEmpty) {
      print('⚠️ Managing missing Casks (in Brewfile but not installed):');
      for (final c in missingCasks) {
        while (true) {
          stdout.write(
            "Action for cask '$c'? [i]nstall, [r]emove from config, or [k]eep: ",
          );
          final choice = stdin.readLineSync()?.trim().toLowerCase() ?? '';
          if (choice == 'i') {
            print('Running: brew install --cask $c');
            await Process.run('brew', ['install', '--cask', c]);
            break;
          } else if (choice == 'r') {
            _removeFromBrewfile(sharedFile, 'cask "$c"');
            _removeFromBrewfile(osFile, 'cask "$c"');
            print("Removed '$c' from Brewfile");
            break;
          } else if (choice == 'k' || choice.isEmpty) {
            print("Kept configuration for '$c'");
            break;
          }
        }
      }
      print('');
    }

    print('✨ Interactive Brewfile triage completed.');
  }

  void _removeFromBrewfile(File file, String targetLine) {
    if (!file.existsSync()) return;
    final lines = file.readAsLinesSync();
    final newLines = lines
        .where((line) => line.trim() != targetLine.trim())
        .toList();
    file.writeAsStringSync('${newLines.join('\n')}\n');
  }

  @override
  Future<UpkeepResult> update({
    bool verbose = false,
    bool cleanup = false,
  }) async {
    Directory? tempDir;
    try {
      final home = _homeDir();
      final sharedBrewfile = File(
        p.join(home, '.config', 'brew', 'Brewfile.shared'),
      );
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
        if (cleanup) '--force-cleanup',
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
