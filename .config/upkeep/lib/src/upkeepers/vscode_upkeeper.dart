import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class VscodeUpkeeper implements Upkeeper {
  final String? homeDirOverride;
  final bool? isLinuxOverride;
  final bool? isMacOverride;

  VscodeUpkeeper({
    this.homeDirOverride,
    this.isLinuxOverride,
    this.isMacOverride,
  });

  @override
  String get id => 'vscode';

  @override
  String get displayName => 'VS Code & Editor Settings';

  @override
  Future<bool> isSupported() async => true;

  String _homeDir() =>
      homeDirOverride ?? Platform.environment['HOME'] ?? Directory.current.path;

  List<String> _getEditorPaths(String home) {
    final paths = <String>[];
    if (isLinuxOverride ?? Platform.isLinux) {
      final config = p.join(home, '.config');
      paths.addAll([
        p.join(config, 'Code', 'User'),
        p.join(config, 'Antigravity IDE', 'User'),
        p.join(config, 'Antigravity', 'User'),
        p.join(
          home,
          '.var',
          'app',
          'com.vscodium.codium',
          'config',
          'VSCodium',
          'User',
        ),
      ]);
    }
    return paths;
  }

  @override
  Future<UpkeepStatus> check() async {
    if (isMacOverride ?? Platform.isMacOS) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.skipped,
        summary: 'TODO - implement the list',
      );
    }

    try {
      final home = _homeDir();
      final sourceSettings = p.join(
        home,
        '.config',
        'vscode-shared',
        'settings.json',
      );
      final sourceKeybindings = p.join(
        home,
        '.config',
        'vscode-shared',
        'keybindings.json',
      );

      if (!File(sourceSettings).existsSync() ||
          !File(sourceKeybindings).existsSync()) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.skipped,
          summary: 'Shared vscode configuration files not found in repository',
        );
      }

      final editorPaths = _getEditorPaths(home);
      final existingDirs = editorPaths
          .where((dir) => Directory(dir).existsSync())
          .toList();

      if (existingDirs.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'No editor config directories found on host',
        );
      }

      final outdatedDetails = <String>[];

      for (final dir in existingDirs) {
        final settingsPath = p.join(dir, 'settings.json');
        final keybindingsPath = p.join(dir, 'keybindings.json');

        if (!_isCorrectSymlink(settingsPath, sourceSettings)) {
          outdatedDetails.add(
            'Missing or incorrect symlink for settings.json in ${p.relative(dir, from: home)}',
          );
        }
        if (!_isCorrectSymlink(keybindingsPath, sourceKeybindings)) {
          outdatedDetails.add(
            'Missing or incorrect symlink for keybindings.json in ${p.relative(dir, from: home)}',
          );
        }
      }

      if (outdatedDetails.isNotEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'VS Code/Editor settings symlinks need reconciliation',
          details: outdatedDetails,
        );
      }

      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.upToDate,
        summary: 'All VS Code/Editor settings symlinks are up to date',
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking VS Code/Editor settings symlinks',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    if (isMacOverride ?? Platform.isMacOS) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'TODO - implement the list',
      );
    }

    try {
      final home = _homeDir();
      final sourceSettings = p.join(
        home,
        '.config',
        'vscode-shared',
        'settings.json',
      );
      final sourceKeybindings = p.join(
        home,
        '.config',
        'vscode-shared',
        'keybindings.json',
      );

      if (!File(sourceSettings).existsSync() ||
          !File(sourceKeybindings).existsSync()) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Shared VS Code configuration files not found',
        );
      }

      final editorPaths = _getEditorPaths(home);
      final existingDirs = editorPaths
          .where((dir) => Directory(dir).existsSync())
          .toList();

      for (final dir in existingDirs) {
        _reconcileFile(p.join(dir, 'settings.json'), sourceSettings);
        _reconcileFile(p.join(dir, 'keybindings.json'), sourceKeybindings);
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: 'Successfully reconciled VS Code/Editor settings symlinks',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Failed to reconcile VS Code/Editor settings symlinks',
        errorMessage: e.toString(),
      );
    }
  }

  bool _isCorrectSymlink(String filePath, String sourcePath) {
    final type = FileSystemEntity.typeSync(filePath, followLinks: false);
    if (type != FileSystemEntityType.link) {
      return false;
    }
    try {
      final target = Link(filePath).targetSync();
      final resolved = p.isAbsolute(target)
          ? target
          : p.normalize(p.join(p.dirname(filePath), target));
      return resolved == p.normalize(sourcePath);
    } catch (_) {
      return false;
    }
  }

  void _reconcileFile(String filePath, String sourcePath) {
    if (_isCorrectSymlink(filePath, sourcePath)) {
      return;
    }

    final fileEntity = File(filePath);
    final linkEntity = Link(filePath);

    final type = FileSystemEntity.typeSync(filePath, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type == FileSystemEntityType.link) {
        linkEntity.deleteSync();
      } else {
        // Back up existing file
        var backupPath = '$filePath.bak';
        var counter = 1;
        while (FileSystemEntity.typeSync(backupPath) !=
            FileSystemEntityType.notFound) {
          backupPath = '$filePath.bak$counter';
          counter++;
        }
        fileEntity.renameSync(backupPath);
      }
    }

    // Create relative symlink
    final relativeTarget = p.relative(sourcePath, from: p.dirname(filePath));
    linkEntity.createSync(relativeTarget, recursive: true);
  }
}
