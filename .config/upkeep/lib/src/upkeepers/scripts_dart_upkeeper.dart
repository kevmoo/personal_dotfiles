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
  final Directory? _installDirOverride;

  ScriptsDartUpkeeper({
    ProcessRunner? processRunner,
    Directory? pubCacheDirOverride,
    Directory? installDirOverride,
  }) : _processRunner = processRunner ?? Process.run,
       _pubCacheDirOverride = pubCacheDirOverride,
       _installDirOverride = installDirOverride;

  @override
  String get id => 'scripts_dart';

  @override
  String get displayName => 'Scripts.dart Package (GitHub)';

  @override
  Future<bool> isSupported() async => _findInstalledSha() != null;

  Directory get _pubCacheDir {
    if (_pubCacheDirOverride != null) return _pubCacheDirOverride!;
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

  Directory get _installDir {
    if (_installDirOverride != null) return _installDirOverride!;
    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isMacOS) {
      return Directory(
        p.join(home, 'Library', 'Application Support', 'Dart', 'install'),
      );
    } else {
      return Directory(p.join(home, '.local', 'share', 'dart', 'install'));
    }
  }

  /// Locate the installed git commit SHA of kevmoo_scripts in the app-bundles directory.
  String? _findInstalledSha() {
    try {
      final gitBundlesDir = Directory(
        p.join(_installDir.path, 'app-bundles', 'kevmoo_scripts', 'git'),
      );
      if (!gitBundlesDir.existsSync()) return null;

      for (final entity in gitBundlesDir.listSync()) {
        if (entity is Directory) {
          final sha = p.basename(entity.path);
          if (sha.isNotEmpty) {
            return sha;
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
          summary: 'scripts package not installed',
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
        'install',
        'kevmoo_scripts@{git: {url: $repoUrl}}',
      ]);

      if (process.exitCode == 0) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message: 'Successfully installed scripts.dart from GitHub ($repoUrl)',
        );
      } else {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to install scripts.dart from GitHub',
          errorMessage: process.stderr.toString().trim(),
        );
      }
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Exception installing scripts.dart',
        errorMessage: e.toString(),
      );
    }
  }
}
