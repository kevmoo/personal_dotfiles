import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../models.dart';
import 'upkeeper.dart';

typedef LatestVersionFetcher = Future<String?> Function(String packageName);

class _DartInstallApp {
  final String name;
  final String type; // 'hosted', 'git', 'path'
  final String currentRef; // version or commit SHA
  final String? latestRef;
  final String? sourceUrl;

  const _DartInstallApp({
    required this.name,
    required this.type,
    required this.currentRef,
    this.latestRef,
    this.sourceUrl,
  });

  bool get isOutdated => latestRef != null && currentRef != latestRef;
}

class DartInstallUpkeeper implements Upkeeper {
  final ProcessRunner _processRunner;
  final LatestVersionFetcher _versionFetcher;
  final Directory? _installDirOverride;

  DartInstallUpkeeper({
    ProcessRunner? processRunner,
    LatestVersionFetcher? versionFetcher,
    this._installDirOverride,
  }) : _processRunner = processRunner ?? Process.run,
       _versionFetcher = versionFetcher ?? _fetchLatestPubDevVersion;

  @override
  String get id => 'dart_install';

  @override
  String get displayName => 'Dart Install Binaries & Tools';

  Directory get _installDir {
    final override = _installDirOverride;
    if (override != null) return override;
    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isMacOS) {
      return Directory(
        p.join(home, 'Library', 'Application Support', 'Dart', 'install'),
      );
    } else {
      final stateDir = Directory(
        p.join(home, '.local', 'state', 'Dart', 'install'),
      );
      if (stateDir.existsSync()) return stateDir;
      return Directory(p.join(home, '.local', 'share', 'dart', 'install'));
    }
  }

  @override
  Future<bool> isSupported() async {
    final dir = _installDir;
    final bundlesDir = Directory(p.join(dir.path, 'app-bundles'));
    return bundlesDir.existsSync();
  }

  static Future<String?> _fetchLatestPubDevVersion(String packageName) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('https://pub.dev/api/packages/$packageName'),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final latest = json['latest'] as Map<String, dynamic>?;
        return latest?['version'] as String?;
      }
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
    return null;
  }

  Future<List<_DartInstallApp>> _discoverInstalledApps() async {
    final appBundlesDir = Directory(p.join(_installDir.path, 'app-bundles'));
    if (!appBundlesDir.existsSync()) return [];

    final apps = <_DartInstallApp>[];

    for (final entity in appBundlesDir.listSync()) {
      if (entity is! Directory) continue;
      final pkgName = p.basename(entity.path);

      // 1. Check hosted bundles: <pkgName>/hosted/<version>/
      final hostedDir = Directory(p.join(entity.path, 'hosted'));
      if (hostedDir.existsSync()) {
        final versions = <Version>[];
        for (final verEntity in hostedDir.listSync()) {
          if (verEntity is! Directory) continue;
          try {
            final ver = Version.parse(p.basename(verEntity.path));
            versions.add(ver);
          } catch (_) {}
        }

        if (versions.isNotEmpty) {
          versions.sort();
          final highestInstalled = versions.last;
          final latestVersionStr = await _versionFetcher(pkgName);

          apps.add(
            _DartInstallApp(
              name: pkgName,
              type: 'hosted',
              currentRef: highestInstalled.toString(),
              latestRef: latestVersionStr,
            ),
          );
        }
      }

      // 2. Check git bundles: <pkgName>/git/<sha>/
      final gitDir = Directory(p.join(entity.path, 'git'));
      if (gitDir.existsSync()) {
        final shaDirs = gitDir.listSync().whereType<Directory>().toList();
        if (shaDirs.isNotEmpty) {
          shaDirs.sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
          final shaEntity = shaDirs.first;
          final sha = p.basename(shaEntity.path);

          String? gitUrl;
          final pubspecLockFile = File(p.join(shaEntity.path, 'pubspec.lock'));
          if (pubspecLockFile.existsSync()) {
            try {
              final lockYaml = loadYaml(pubspecLockFile.readAsStringSync());
              if (lockYaml is YamlMap && lockYaml['packages'] is YamlMap) {
                final pkgEntry = lockYaml['packages'][pkgName] as YamlMap?;
                final desc = pkgEntry?['description'] as YamlMap?;
                if (desc != null && desc['url'] != null) {
                  gitUrl = desc['url'].toString();
                }
              }
            } catch (_) {}
          }

          String? remoteSha;
          if (gitUrl != null) {
            try {
              final lsResult = await _processRunner('git', [
                'ls-remote',
                gitUrl,
                'HEAD',
              ]);
              if (lsResult.exitCode == 0) {
                final out = lsResult.stdout.toString().trim();
                final parts = out.split(RegExp(r'\s+'));
                if (parts.isNotEmpty && parts.first.isNotEmpty) {
                  remoteSha = parts.first;
                }
              }
            } catch (_) {}
          }

          apps.add(
            _DartInstallApp(
              name: pkgName,
              type: 'git',
              currentRef: sha,
              latestRef: remoteSha,
              sourceUrl: gitUrl,
            ),
          );
        }
      }

      // 3. Check local path bundles: <pkgName>/local/
      final localDir = Directory(p.join(entity.path, 'local'));
      if (localDir.existsSync()) {
        String? sourcePath;
        final pubspecLockFile = File(p.join(localDir.path, 'pubspec.lock'));
        if (pubspecLockFile.existsSync()) {
          try {
            final lockYaml = loadYaml(pubspecLockFile.readAsStringSync());
            if (lockYaml is YamlMap && lockYaml['packages'] is YamlMap) {
              final pkgEntry = lockYaml['packages'][pkgName] as YamlMap?;
              final desc = pkgEntry?['description'] as YamlMap?;
              if (desc != null && desc['path'] != null) {
                sourcePath = desc['path'].toString();
              }
            }
          } catch (_) {}
        }

        String currentRef = 'installed';
        String? latestRef;

        if (sourcePath != null && Directory(sourcePath).existsSync()) {
          try {
            final bundleDir = Directory(p.join(localDir.path, 'bundle'));
            final bundleMtime = bundleDir.existsSync()
                ? bundleDir.statSync().modified.millisecondsSinceEpoch ~/ 1000
                : 0;

            final logRes = await _processRunner('git', [
              '-C',
              sourcePath,
              'log',
              '-1',
              '--format=%ct %h',
            ]);
            if (logRes.exitCode == 0) {
              final parts = logRes.stdout.toString().trim().split(' ');
              if (parts.isNotEmpty) {
                final commitEpoch = int.tryParse(parts[0]) ?? 0;
                final commitShort = parts.length > 1 ? parts[1] : 'HEAD';
                if (commitEpoch > bundleMtime) {
                  currentRef = 'built earlier';
                  latestRef = 'newer commit $commitShort';
                }
              }
            }
          } catch (_) {}
        }

        apps.add(
          _DartInstallApp(
            name: pkgName,
            type: 'local',
            currentRef: currentRef,
            latestRef: latestRef,
            sourceUrl: sourcePath,
          ),
        );
      }
    }

    return apps;
  }

  @override
  Future<UpkeepStatus> check() async {
    try {
      final apps = await _discoverInstalledApps();
      if (apps.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: 'No tools installed via dart install',
        );
      }

      final outdated = apps.where((a) => a.isOutdated).toList();

      if (outdated.isEmpty) {
        final names = apps.map((a) => a.name).toSet().toList()..sort();
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: '${names.length} tool(s) up to date (${names.join(', ')})',
        );
      }

      final outdatedDetails = <String>[];
      for (final a in outdated) {
        if (a.type == 'hosted') {
          outdatedDetails.add('${a.name}: ${a.currentRef} -> ${a.latestRef}');
        } else if (a.type == 'git') {
          final currShort = a.currentRef.length >= 7
              ? a.currentRef.substring(0, 7)
              : a.currentRef;
          final remShort = (a.latestRef != null && a.latestRef!.length >= 7)
              ? a.latestRef!.substring(0, 7)
              : (a.latestRef ?? 'unknown');
          outdatedDetails.add('${a.name} (git): $currShort -> $remShort');
        } else if (a.type == 'local') {
          outdatedDetails.add(
            '${a.name} (local): ${a.currentRef} -> ${a.latestRef}',
          );
        }
      }

      final outdatedNames = outdated.map((a) => a.name).toSet().join(', ');
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.outdated,
        summary: '${outdated.length} tool(s) outdated ($outdatedNames)',
        details: [
          '${outdated.length} of ${apps.length} installed tool(s) have updates available:',
          ...outdatedDetails.map((d) => '  • $d'),
        ],
      );
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception checking dart install tools',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    try {
      final apps = await _discoverInstalledApps();
      final outdated = apps.where((a) => a.isOutdated).toList();

      if (outdated.isEmpty) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: true,
          message: 'All installed Dart tools are up to date',
        );
      }

      final upgraded = <String>[];
      final errors = <String>[];

      for (final app in outdated) {
        ProcessResult res;
        if (app.type == 'hosted') {
          res = await _processRunner('dart', ['install', app.name]);
        } else if (app.type == 'git') {
          final url = app.sourceUrl;
          if (url == null) {
            errors.add('${app.name}: missing remote Git URL in pubspec.lock');
            continue;
          }
          res = await _processRunner('dart', [
            'install',
            '${app.name}@{git: {url: $url}}',
          ]);
        } else if (app.type == 'local') {
          final path = app.sourceUrl;
          if (path == null) {
            errors.add(
              '${app.name}: missing local source path in pubspec.lock',
            );
            continue;
          }
          res = await _processRunner('dart', [
            'install',
            '${app.name}@{path: $path}',
          ]);
        } else {
          errors.add('${app.name}: unknown package source type ${app.type}');
          continue;
        }

        if (res.exitCode == 0) {
          upgraded.add(app.name);
        } else {
          errors.add('${app.name}: ${res.stderr.toString().trim()}');
        }
      }

      if (errors.isNotEmpty) {
        return UpkeepResult(
          upkeeperId: id,
          displayName: displayName,
          success: false,
          message: 'Failed to upgrade some Dart tools: ${errors.join('; ')}',
          errorMessage: errors.join('\n'),
        );
      }

      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message:
            'Successfully updated ${upgraded.length} Dart tool(s): ${upgraded.join(', ')}',
      );
    } catch (e) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: false,
        message: 'Exception updating Dart install tools',
        errorMessage: e.toString(),
      );
    }
  }
}
