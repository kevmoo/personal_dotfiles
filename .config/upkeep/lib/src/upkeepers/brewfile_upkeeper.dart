import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class BrewfileUpkeeper implements Upkeeper {
  final bool? isCloudtopOverride;
  final bool? isMacOSOverride;
  final String Function()? homeDirOverride;
  final ProcessRunner _processRunner;
  final String? Function()? inputReader;
  final void Function(String)? outputWriter;

  BrewfileUpkeeper({
    this.isCloudtopOverride,
    this.isMacOSOverride,
    this.homeDirOverride,
    ProcessRunner? processRunner,
    this.inputReader,
    this.outputWriter,
  }) : _processRunner = processRunner ?? Process.run;

  @override
  String get id => 'brewfile';

  @override
  String get displayName => 'Homebrew Brewfile Sync';

  bool _isMacOS() => isMacOSOverride ?? Platform.isMacOS;

  void _write(String text) {
    if (outputWriter != null) {
      outputWriter!(text);
    } else {
      stdout.write(text);
    }
  }

  void _writeln([String text = '']) => _write('$text\n');

  String _readLine() =>
      (inputReader != null ? inputReader!() : stdin.readLineSync())
          ?.trim()
          .toLowerCase() ??
      '';

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
      final result = await _processRunner('which', ['brew']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _homeDir() => homeDirOverride != null
      ? homeDirOverride!()
      : (Platform.environment['HOME'] ?? Directory.current.path);

  String _getOsBrewfilePath() {
    final home = _homeDir();
    if (_isMacOS()) {
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
    final res = await _processRunner('brew', args);
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
        state: totalMissing > 0
            ? UpkeepState.outdated
            : UpkeepState.needsTriage,
        summary: summaryParts.join(', '),
        details: details,
        actionHint: totalUnmanaged > 0 ? 'upkeep triage' : null,
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
      _writeln(
        '✨ All Homebrew packages are fully synchronized with Brewfiles!',
      );
      return;
    }

    _writeln('\n🍏 Interactive Brewfile Triage\n');

    await _triageUnmanagedGroup(
      audit.unmanagedFormulae,
      header: '📦 Managing unmanaged Formulae:',
      kind: 'formula',
      directive: 'brew',
      files: (shared: audit.sharedFile, os: audit.osFile),
    );
    await _triageUnmanagedGroup(
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

    _writeln('✨ Interactive Brewfile triage completed.');
  }

  Future<void> _triageUnmanagedGroup(
    List<String> items, {
    required String header,
    required String kind,
    required String directive,
    required ({File shared, File os}) files,
  }) async {
    if (items.isEmpty) return;
    final (osLabel, osKey) = _isMacOS() ? ('mac', 'm') : ('linux', 'l');
    _writeln(header);
    for (final item in items) {
      await _triageUnmanagedItem(
        item,
        kind: kind,
        directive: directive,
        osLabel: osLabel,
        osKey: osKey,
        files: files,
      );
    }
    _writeln();
  }

  Future<void> _triageUnmanagedItem(
    String item, {
    required String kind,
    required String directive,
    required String osLabel,
    required String osKey,
    required ({File shared, File os}) files,
  }) async {
    final uninstallArgs = directive == 'cask'
        ? ['uninstall', '--cask', item]
        : ['uninstall', item];
    while (true) {
      _write(
        "Action for unmanaged $kind '$item'? "
        '[r]emove, [$osKey]$osLabel, [s]hared, or [d]o nothing: ',
      );
      final choice = _readLine();
      switch (choice) {
        case 'r':
          _writeln('Running: brew ${uninstallArgs.join(' ')}');
          final res = await _processRunner('brew', uninstallArgs);
          if (res.exitCode == 0) {
            _writeln("Removed '$item'");
          } else {
            _writeln(
              "Failed to remove '$item': ${res.stderr.toString().trim()}",
            );
          }
          return;
        case _ when choice == osKey:
          _appendBrewfileEntry(files.os, '$directive "$item"');
          _writeln("Added '$item' to Brewfile.$osLabel");
          return;
        case 's':
          _appendBrewfileEntry(files.shared, '$directive "$item"');
          _writeln("Added '$item' to Brewfile.shared");
          return;
        case 'd' || 'n' || '':
          _writeln("Skipped '$item'");
          return;
      }
    }
  }

  void _appendBrewfileEntry(File file, String entry) {
    file.parent.createSync(recursive: true);
    var prefix = '';
    if (file.existsSync()) {
      final existing = file.readAsStringSync();
      if (existing.isNotEmpty && !existing.endsWith('\n')) {
        prefix = '\n';
      }
    }
    file.writeAsStringSync('$prefix$entry\n', mode: FileMode.append);
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
    _writeln(header);
    for (final item in items) {
      await _triageMissingItem(
        item,
        kind: kind,
        directive: directive,
        baseInstallArgs: baseInstallArgs,
        files: files,
      );
    }
    _writeln();
  }

  Future<void> _triageMissingItem(
    String item, {
    required String kind,
    required String directive,
    required List<String> baseInstallArgs,
    required ({File shared, File os}) files,
  }) async {
    while (true) {
      _write(
        "Action for $kind '$item'? [i]nstall, [r]emove from config, or [k]eep: ",
      );
      final choice = _readLine();
      switch (choice) {
        case 'i':
          final installArgs = [...baseInstallArgs, item];
          _writeln('Running: brew ${installArgs.join(' ')}');
          await _processRunner('brew', installArgs);
          return;
        case 'r':
          _removeFromBrewfile(files.shared, '$directive "$item"');
          _removeFromBrewfile(files.os, '$directive "$item"');
          _writeln("Removed '$item' from Brewfile");
          return;
        case 'k' || '':
          _writeln("Kept configuration for '$item'");
          return;
      }
    }
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
      final bundleProc = await _processRunner('brew', bundleArgs);
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
