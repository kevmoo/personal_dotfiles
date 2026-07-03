import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models.dart';
import 'upkeeper.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class ScriptsDartUpkeeper implements Upkeeper {
  static const String repoUrl = 'https://github.com/kevmoo/scripts.dart.git';

  final ProcessRunner _processRunner;
  final Directory? _pubCacheDirOverride;

  ScriptsDartUpkeeper({ProcessRunner? processRunner, this._pubCacheDirOverride})
    : _processRunner = processRunner ?? Process.run;

  @override
  String get id => 'scripts_dart';

  @override
  String get displayName => 'Scripts.dart Package (GitHub)';

  @override
  Future<bool> isSupported() async {
    try {
      final result = await _processRunner('which', ['dart']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Directory get _pubCacheDir {
    if (_pubCacheDirOverride != null) return _pubCacheDirOverride;
    final envCache = Platform.environment['PUB_CACHE'];
    if (envCache != null && envCache.isNotEmpty) {
      return Directory(envCache);
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return Directory(p.join(home, '.pub-cache'));
  }

  /// Locate the installed git commit SHA from pubspec.lock in pub-cache.
  String? _findInstalledSha() {
    try {
      final globalPackagesDir = Directory(
        p.join(_pubCacheDir.path, 'global_packages'),
      );
      if (!globalPackagesDir.existsSync()) return null;

      for (final entity in globalPackagesDir.listSync()) {
        if (entity is Directory) {
          final lockFile = File(p.join(entity.path, 'pubspec.lock'));
          if (lockFile.existsSync()) {
            final content = lockFile.readAsStringSync();
            final yaml = loadYaml(content);
            if (yaml is YamlMap && yaml.containsKey('packages')) {
              final packages = yaml['packages'];
              if (packages is YamlMap) {
                for (final entry in packages.entries) {
                  final pkg = entry.value;
                  if (pkg is YamlMap) {
                    final desc = pkg['description'];
                    if (desc is YamlMap) {
                      final url = desc['url']?.toString() ?? '';
                      if (url.contains('scripts.dart')) {
                        final resolvedRef = desc['resolved-ref']?.toString();
                        if (resolvedRef != null && resolvedRef.isNotEmpty) {
                          return resolvedRef;
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Directory? _findGitCacheDir() {
    try {
      final gitCacheDir = Directory(p.join(_pubCacheDir.path, 'git', 'cache'));
      if (!gitCacheDir.existsSync()) return null;

      for (final entity in gitCacheDir.listSync()) {
        if (entity is Directory &&
            p.basename(entity.path).contains('scripts.dart')) {
          return entity;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final installedSha = _findInstalledSha();
      if (installedSha == null) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'scripts package not activated globally',
        );
      }

      final shortLocal = installedSha.length >= 7
          ? installedSha.substring(0, 7)
          : installedSha;

      final cacheDir = _findGitCacheDir();
      if (cacheDir != null) {
        // Fetch latest HEAD into bare cache repo
        final fetchRes = await _processRunner('git', [
          '-c',
          'safe.bareRepository=all',
          '-C',
          cacheDir.path,
          'fetch',
          'origin',
          'HEAD',
        ]);

        if (fetchRes.exitCode == 0) {
          // Get local date
          final localDateRes = await _processRunner('git', [
            '-c',
            'safe.bareRepository=all',
            '-C',
            cacheDir.path,
            'log',
            '-1',
            '--format=%cs',
            installedSha,
          ]);
          final localDate = localDateRes.stdout.toString().trim();

          // Get remote SHA & date from FETCH_HEAD
          final remoteLogRes = await _processRunner('git', [
            '-c',
            'safe.bareRepository=all',
            '-C',
            cacheDir.path,
            'log',
            '-1',
            '--format=%H %cs',
            'FETCH_HEAD',
          ]);
          final remoteLogOutput = remoteLogRes.stdout.toString().trim();
          final remoteParts = remoteLogOutput.split(RegExp(r'\s+'));

          if (remoteParts.length >= 2) {
            final remoteSha = remoteParts[0];
            final remoteDate = remoteParts[1];
            final shortRemote = remoteSha.length >= 7
                ? remoteSha.substring(0, 7)
                : remoteSha;

            if (installedSha == remoteSha ||
                installedSha.startsWith(remoteSha) ||
                remoteSha.startsWith(installedSha)) {
              final dateStr = localDate.isNotEmpty ? ', $localDate' : '';
              return UpkeepStatus(
                upkeeperId: id,
                displayName: displayName,
                state: UpkeepState.upToDate,
                summary: 'Up to date ($shortLocal$dateStr)',
              );
            }

            // Calculate commits behind
            final countRes = await _processRunner('git', [
              '-c',
              'safe.bareRepository=all',
              '-C',
              cacheDir.path,
              'rev-list',
              '--count',
              '$installedSha..FETCH_HEAD',
            ]);
            final countStr = countRes.stdout.toString().trim();
            final count = int.tryParse(countStr) ?? 0;

            final behindMsg = count > 0
                ? '$count commit${count == 1 ? '' : 's'} behind: '
                : '';
            final localPart = localDate.isNotEmpty
                ? '$shortLocal ($localDate)'
                : shortLocal;
            final remotePart = remoteDate.isNotEmpty
                ? '$shortRemote ($remoteDate)'
                : shortRemote;

            return UpkeepStatus(
              upkeeperId: id,
              displayName: displayName,
              state: UpkeepState.outdated,
              summary: '$behindMsg$localPart -> $remotePart',
            );
          }
        }
      }

      // Fallback if cache directory or git operations fail: fallback to git ls-remote SHA check
      final gitResult = await _processRunner('git', [
        'ls-remote',
        repoUrl,
        'HEAD',
      ]);
      if (gitResult.exitCode != 0) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary:
              'Activated globally at $shortLocal (unable to fetch remote SHA)',
        );
      }

      final remoteOutput = gitResult.stdout.toString().trim();
      final remoteSha = remoteOutput.split(RegExp(r'\s+')).first;
      if (remoteSha.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Activated globally at $shortLocal',
        );
      }

      final shortRemote = remoteSha.length >= 7
          ? remoteSha.substring(0, 7)
          : remoteSha;

      if (installedSha == remoteSha ||
          installedSha.startsWith(remoteSha) ||
          remoteSha.startsWith(installedSha)) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'Up to date ($shortLocal)',
        );
      } else {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.outdated,
          summary: 'Update available: $shortLocal -> $shortRemote',
        );
      }
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking global scripts package',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final process = await _processRunner('dart', [
        'pub',
        'global',
        'activate',
        '--source',
        'git',
        repoUrl,
      ]);

      if (process.exitCode == 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message: 'Successfully activated scripts.dart from GitHub ($repoUrl)',
        );
      } else {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to activate scripts.dart from GitHub',
          errorMessage: process.stderr.toString().trim(),
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Exception activating scripts.dart',
        errorMessage: e.toString(),
      );
    }
  }
}
