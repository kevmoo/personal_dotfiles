import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class LocalBinUpkeeper implements Upkeeper {
  static const _ignoredNames = {'__pycache__', '.DS_Store', 'LICENSE.txt'};

  static const _allowlistFiles = [
    'local_bin_allowlist',
    'local_bin_allowlist.corp',
    'local_bin_allowlist.local',
  ];

  final String Function()? homeDirOverride;
  final ProcessRunner _processRunner;

  LocalBinUpkeeper({this.homeDirOverride, ProcessRunner? processRunner})
    : _processRunner = processRunner ?? Process.run;

  @override
  String get id => 'local_bin';

  @override
  String get displayName => '~/.local/bin Hygiene';

  String _homeDir() => homeDirOverride != null
      ? homeDirOverride!()
      : (Platform.environment['HOME'] ?? Directory.current.path);

  String _localBinDir(String home) => p.join(home, '.local', 'bin');

  @override
  Future<bool> isSupported() async =>
      Directory(_localBinDir(_homeDir())).existsSync();

  @override
  Future<UpkeepStatus> check() async {
    try {
      final home = _homeDir();
      final binDir = Directory(_localBinDir(home));
      if (!binDir.existsSync()) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary: '~/.local/bin directory not present',
        );
      }

      final known = <String>{
        ...await _gitTrackedBinaries(home, '.dotfiles'),
        ...await _gitTrackedBinaries(home, '.dotfiles-corp'),
        ..._readAllowlists(home),
      };

      final entries =
          binDir
              .listSync(followLinks: false)
              .where((e) => !_ignoredNames.contains(p.basename(e.path)))
              .toList()
            ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      final untracked = <String>[];
      final brokenSymlinks = <String>[];

      for (final entry in entries) {
        final name = p.basename(entry.path);
        final isLink = FileSystemEntity.isLinkSync(entry.path);
        if (isLink &&
            FileSystemEntity.typeSync(entry.path, followLinks: true) ==
                FileSystemEntityType.notFound) {
          brokenSymlinks.add(
            '$name -> ${Link(entry.path).targetSync()} (broken symlink)',
          );
          continue;
        }
        if (!known.contains(name)) {
          final label = isLink
              ? '$name -> ${Link(entry.path).targetSync()}'
              : name;
          untracked.add(label);
        }
      }

      if (untracked.isEmpty && brokenSymlinks.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary:
              'All ${entries.length} entries in ~/.local/bin are tracked or allowlisted',
        );
      }

      return _buildOutdatedStatus(untracked, brokenSymlinks);
    } catch (e) {
      return UpkeepStatus(
        upkeeperId: id,
        displayName: displayName,
        state: UpkeepState.error,
        summary: 'Exception auditing ~/.local/bin',
        errorMessage: e.toString(),
      );
    }
  }

  UpkeepStatus _buildOutdatedStatus(
    List<String> untracked,
    List<String> brokenSymlinks,
  ) {
    final parts = <String>[
      if (untracked.isNotEmpty) '${untracked.length} untracked',
      if (brokenSymlinks.isNotEmpty)
        '${brokenSymlinks.length} broken symlink(s)',
    ];
    final details = <String>[
      if (brokenSymlinks.isNotEmpty) ...[
        'Broken symlinks:',
        ...brokenSymlinks.map((s) => '  $s'),
      ],
      if (untracked.isNotEmpty) ...[
        'Untracked ~/.local/bin entries:',
        ...untracked.map((s) => '  $s'),
      ],
      'Track via "dot add -f" / "dotcorp add -f", allowlist in ~/.config/upkeep/local_bin_allowlist*, or remove.',
    ];
    return UpkeepStatus(
      upkeeperId: id,
      displayName: displayName,
      state: UpkeepState.outdated,
      summary: '${parts.join(', ')} in ~/.local/bin',
      details: details,
    );
  }

  Future<Set<String>> _gitTrackedBinaries(
    String home,
    String bareDirName,
  ) async {
    final gitDir = p.join(home, bareDirName);
    if (!Directory(gitDir).existsSync()) return const <String>{};

    final proc = await _processRunner('git', [
      '-C',
      home,
      '--git-dir=$gitDir',
      '--work-tree=$home',
      'ls-files',
      '.local/bin',
    ]);
    if (proc.exitCode != 0) return const <String>{};

    return proc.stdout
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map(p.basename)
        .toSet();
  }

  Set<String> _readAllowlists(String home) {
    final names = <String>{};
    final upkeepDir = p.join(home, '.config', 'upkeep');
    for (final fileName in _allowlistFiles) {
      final file = File(p.join(upkeepDir, fileName));
      if (!file.existsSync()) continue;
      for (final raw in file.readAsLinesSync()) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        names.add(line);
      }
    }
    return names;
  }

  @override
  Future<UpkeepResult> update({bool verbose = false}) async {
    final status = await check();
    if (status.isUpToDate) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: status.summary,
      );
    }
    return UpkeepResult(
      upkeeperId: id,
      displayName: displayName,
      success: false,
      message: 'Manual triage required: ${status.summary}',
      errorMessage: status.details.join('\n'),
    );
  }
}
