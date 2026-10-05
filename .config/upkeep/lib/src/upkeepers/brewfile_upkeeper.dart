import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class BrewfileUpkeeper implements Upkeeper {
  final bool? isCloudtopOverride;

  BrewfileUpkeeper({this.isCloudtopOverride});

  @override
  String get id => 'brewfile';

  @override
  String get displayName => 'Homebrew Brewfile Sync';

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

  Future<Set<String>> _brewSet(List<String> args) async {
    final res = await Process.run('brew', args);
    if (res.exitCode != 0) return {};
    return res.stdout
        .toString()
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Future<
    ({
      File sharedFile,
      File osFile,
      List<String> missingFormulae,
      List<String> missingCasks,
      List<String> unmanagedFormulae,
      List<String> unmanagedCasks,
    })
  >
  _auditBrewfiles() async {
    final home = _homeDir();
    final sharedPath = p.join(home, '.config', 'brew', 'Brewfile.shared');
    final osPath = _getOsBrewfilePath();

    final expectedFormulae = {
      ..._parseBrewfileEntries(sharedPath, 'brew'),
      ..._parseBrewfileEntries(osPath, 'brew'),
    };
    final expectedCasks = {
      ..._parseBrewfileEntries(sharedPath, 'cask'),
      ..._parseBrewfileEntries(osPath, 'cask'),
    };

    final installedLeaves = await _brewSet(['leaves']);
    final allFormulae = await _brewSet(['list', '--formula']);
    final installedCasks = await _brewSet(['list', '--cask']);

    return (
      sharedFile: File(sharedPath),
      osFile: File(osPath),
      missingFormulae: expectedFormulae
          .where((f) => !_matchesExpected(f, allFormulae))
          .toList(),
      missingCasks: expectedCasks
          .where((c) => !_matchesExpected(c, installedCasks))
          .toList(),
      unmanagedFormulae: installedLeaves
          .where((f) => !_matchesExpected(f, expectedFormulae))
          .toList(),
      unmanagedCasks: installedCasks
          .where((c) => !_matchesExpected(c, expectedCasks))
          .toList(),
    );
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final audit = await _auditBrewfiles();
      final details = <String>[
        for (final f in audit.missingFormulae) 'Missing formula: $f',
        for (final c in audit.missingCasks) 'Missing cask: $c',
        for (final f in audit.unmanagedFormulae) 'Unmanaged formula: $f',
        for (final c in audit.unmanagedCasks) 'Unmanaged cask: $c',
      ];

      final totalMissing =
          audit.missingFormulae.length + audit.missingCasks.length;
      final totalUnmanaged =
          audit.unmanagedFormulae.length + audit.unmanagedCasks.length;

      if (totalMissing + totalUnmanaged == 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Brewfile packages & casks fully synchronized',
        );
      }

      final summaryParts = <String>[
        if (totalMissing > 0) '$totalMissing missing from Brewfile',
        if (totalUnmanaged > 0) '$totalUnmanaged unmanaged in Brewfile',
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
    final audit = await _auditBrewfiles();
    if (audit.unmanagedFormulae.isEmpty &&
        audit.unmanagedCasks.isEmpty &&
        audit.missingFormulae.isEmpty &&
        audit.missingCasks.isEmpty) {
      print('✨ All Homebrew packages are fully synchronized with Brewfiles!');
      return;
    }

    print('\n🍏 Interactive Brewfile Triage\n');

    _triageUnmanagedGroup(
      audit.unmanagedFormulae,
      header: '📦 Managing unmanaged Formulae:',
      kind: 'formula',
      directive: 'brew',
      files: (shared: audit.sharedFile, os: audit.osFile),
    );
    _triageUnmanagedGroup(
      audit.unmanagedCasks,
      header: '🖥️ Managing unmanaged Casks:',
      kind: 'cask',
      directive: 'cask',
      files: (shared: audit.sharedFile, os: audit.osFile),
    );
    await _triageMissingGroup(
      audit.missingFormulae,
      header: '⚠️ Managing missing Formulae (in Brewfile but not installed):',
      kind: 'formula',
      directive: 'brew',
      files: (shared: audit.sharedFile, os: audit.osFile),
    );
    await _triageMissingGroup(
      audit.missingCasks,
      header: '⚠️ Managing missing Casks (in Brewfile but not installed):',
      kind: 'cask',
      directive: 'cask',
      files: (shared: audit.sharedFile, os: audit.osFile),
    );

    print('✨ Interactive Brewfile triage completed.');
  }

  void _triageUnmanagedGroup(
    List<String> items, {
    required String header,
    required String kind,
    required String directive,
    required ({File shared, File os}) files,
  }) {
    if (items.isEmpty) return;
    final (osLabel, osKey) = Platform.isMacOS ? ('mac', 'm') : ('linux', 'l');
    print(header);
    for (final item in items) {
      var resolved = false;
      while (!resolved) {
        stdout.write(
          "Add $kind '$item' to Brewfile? [s]hared, [$osKey]$osLabel, or [n]o: ",
        );
        final choice = stdin.readLineSync()?.trim().toLowerCase() ?? '';
        switch (choice) {
          case 's':
            files.shared.writeAsStringSync(
              '$directive "$item"\n',
              mode: FileMode.append,
            );
            print("Added '$item' to Brewfile.shared");
            resolved = true;
          case _ when choice == osKey:
            files.os.writeAsStringSync(
              '$directive "$item"\n',
              mode: FileMode.append,
            );
            print("Added '$item' to Brewfile.$osLabel");
            resolved = true;
          case 'n' || '':
            print("Skipped '$item'");
            resolved = true;
        }
      }
    }
    print('');
  }

  Future<void> _triageMissingGroup(
    List<String> items, {
    required String header,
    required String kind,
    required String directive,
    required ({File shared, File os}) files,
  }) async {
    if (items.isEmpty) return;
    final baseInstallArgs = directive == 'cask'
        ? const ['install', '--cask']
        : const ['install'];
    print(header);
    for (final item in items) {
      var resolved = false;
      while (!resolved) {
        stdout.write(
          "Action for $kind '$item'? [i]nstall, [r]emove from config, or [k]eep: ",
        );
        final choice = stdin.readLineSync()?.trim().toLowerCase() ?? '';
        switch (choice) {
          case 'i':
            final installArgs = [...baseInstallArgs, item];
            print('Running: brew ${installArgs.join(' ')}');
            await Process.run('brew', installArgs);
            resolved = true;
          case 'r':
            _removeFromBrewfile(files.shared, '$directive "$item"');
            _removeFromBrewfile(files.os, '$directive "$item"');
            print("Removed '$item' from Brewfile");
            resolved = true;
          case 'k' || '':
            print("Kept configuration for '$item'");
            resolved = true;
        }
      }
    }
    print('');
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
