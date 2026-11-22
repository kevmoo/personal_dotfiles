import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'upkeeper.dart';

class LocalBinUpkeeper implements Upkeeper {
  static const _ignoredNames = {'__pycache__', '.DS_Store', 'LICENSE.txt'};
  static final _staleAgyBackupPattern = RegExp(r'^agy\.\d+\.old$');

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

      final scan = await _scanBinDir(home, binDir);

      if (scan.untracked.isEmpty &&
          scan.brokenSymlinks.isEmpty &&
          scan.staleBackups.isEmpty) {
        return UpkeepStatus(
          upkeeperId: id,
          displayName: displayName,
          state: UpkeepState.upToDate,
          summary:
              'All ${scan.total} entries in ~/.local/bin are tracked or allowlisted',
        );
      }

      if (scan.untracked.isEmpty && scan.brokenSymlinks.isEmpty) {
        return _buildStaleBackupsStatus(scan.staleBackups);
      }

      return _buildTriageStatus(
        scan.untracked,
        scan.brokenSymlinks,
        scan.staleBackups,
      );
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

  Future<
    ({
      List<String> untracked,
      List<String> brokenSymlinks,
      List<File> staleBackups,
      int total,
    })
  >
  _scanBinDir(String home, Directory binDir) async {
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
    final staleBackups = <File>[];

    for (final entry in entries) {
      final name = p.basename(entry.path);
      final isLink = FileSystemEntity.isLinkSync(entry.path);
      if (!isLink && entry is File && _staleAgyBackupPattern.hasMatch(name)) {
        staleBackups.add(entry);
        continue;
      }
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

    return (
      untracked: untracked,
      brokenSymlinks: brokenSymlinks,
      staleBackups: staleBackups,
      total: entries.length,
    );
  }

  UpkeepStatus _buildStaleBackupsStatus(List<File> staleBackups) {
    final names = staleBackups.map((f) => p.basename(f.path)).toList();
    return UpkeepStatus(
      upkeeperId: id,
      displayName: displayName,
      state: UpkeepState.outdated,
      summary: '${names.length} stale agy backup(s) in ~/.local/bin',
      details: [
        'Stale agy self-update backups (auto-removed by "upkeep update local_bin"):',
        ...names.map((n) => '  $n'),
      ],
    );
  }

  UpkeepStatus _buildTriageStatus(
    List<String> untracked,
    List<String> brokenSymlinks,
    List<File> staleBackups,
  ) {
    final parts = <String>[
      if (untracked.isNotEmpty) '${untracked.length} untracked',
      if (brokenSymlinks.isNotEmpty)
        '${brokenSymlinks.length} broken symlink(s)',
      if (staleBackups.isNotEmpty) '${staleBackups.length} stale agy backup(s)',
    ];
    final details = <String>[
      if (brokenSymlinks.isNotEmpty) ...[
        'Broken symlinks:',
        ...brokenSymlinks.map((s) => '  $s'),
      ],
      if (staleBackups.isNotEmpty) ...[
        'Stale agy self-update backups (auto-removed by "upkeep update local_bin"):',
        ...staleBackups.map((f) => '  ${p.basename(f.path)}'),
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
      state: UpkeepState.needsTriage,
      summary: '${parts.join(', ')} in ~/.local/bin',
      details: details,
      actionHint: 'Track via "dot add -f", allowlist in ~/.config/upkeep/local_bin_allowlist*, or remove',
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
    final home = _homeDir();
    final binDir = Directory(_localBinDir(home));
    if (!binDir.existsSync()) {
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: '~/.local/bin directory not present',
      );
    }

    final scan = await _scanBinDir(home, binDir);
    final removed = <String>[];
    for (final file in scan.staleBackups) {
      if (file.existsSync()) {
        file.deleteSync();
        removed.add(p.basename(file.path));
      }
    }

    if (scan.untracked.isEmpty && scan.brokenSymlinks.isEmpty) {
      final message = removed.isEmpty
          ? 'All ${scan.total} entries in ~/.local/bin are tracked or allowlisted'
          : 'Removed ${removed.length} stale agy backup(s): ${removed.join(', ')}';
      return UpkeepResult(
        upkeeperId: id,
        displayName: displayName,
        success: true,
        message: message,
      );
    }

    final status = _buildTriageStatus(
      scan.untracked,
      scan.brokenSymlinks,
      const [],
    );
    final prefix = removed.isEmpty
        ? ''
        : 'Removed ${removed.length} stale agy backup(s) (${removed.join(', ')}); ';
    return UpkeepResult(
      upkeeperId: id,
      displayName: displayName,
      success: false,
      message: '${prefix}Manual triage required: ${status.summary}',
      errorMessage: status.details.join('\n'),
    );
  }
}
