import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

class AuditCommand extends Command<void> {
  @override
  final String name = 'audit';

  @override
  final String description =
      'Audit the sync and branch status of local git repositories.';

  AuditCommand() {
    argParser
      ..addFlag(
        'sync',
        abbr: 's',
        negatable: false,
        help: 'Pull tracking branch if behind (fast-forward only)',
      )
      ..addFlag(
        'write',
        abbr: 'w',
        negatable: false,
        help: 'Write results table back to target directory README.md',
      );
  }

  @override
  Future<void> run() async {
    final sync = argResults!['sync'] as bool;
    final writeReadme = argResults!['write'] as bool;
    final positional = argResults!.rest;

    final targetPath = positional.isNotEmpty
        ? positional.first
        : '${Platform.environment['HOME']}/github/kevmoo';

    final targetDir = Directory(targetPath);
    if (!targetDir.existsSync()) {
      stderr.writeln('Target directory not found: $targetPath');
      exitCode = 1;
      return;
    }

    final rows = await _collectRows(targetDir, sync: sync);
    final output = _renderReport(rows);
    print(output);

    if (writeReadme) {
      File('$targetPath/README.md').writeAsStringSync(output);
      stderr.writeln('Updated $targetPath/README.md');
    }
  }
}

/// Scans [targetDir] and produces one row per repository, sorted for display.
///
/// Git-backed directories are audited in parallel; plain directories are
/// reported as local scratch space.
Future<List<Map<String, String>>> _collectRows(
  Directory targetDir, {
  required bool sync,
}) async {
  final entities = targetDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final rows = <Map<String, String>>[];
  final futures = <Future<void>>[];

  for (final dir in entities) {
    final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name.startsWith('.') || name.startsWith('_')) continue;

    final sdkConstraint = _sdkConstraint(dir);

    final gitType = FileSystemEntity.typeSync('${dir.path}/.git');
    if (gitType == FileSystemEntityType.notFound) {
      rows.add({
        'name': name,
        'path': dir.path,
        'remote': 'None',
        'sdk': sdkConstraint,
        'date': 'N/A',
        'status': '⚪ Local scratch (No .git repo)',
      });
      continue;
    }

    futures.add(
      _auditRepo(
        dir,
        name: name,
        sdkConstraint: sdkConstraint,
        sync: sync,
      ).then(rows.add),
    );
  }

  await Future.wait(futures);
  rows.sort(_compareRows);
  return rows;
}

/// Extracts the `environment: sdk:` constraint from a directory's
/// `pubspec.yaml`, or `'-'` when absent or unreadable.
String _sdkConstraint(Directory dir) {
  final pubspecFile = File('${dir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) return '-';
  try {
    final pubspec = Pubspec.parse(
      pubspecFile.readAsStringSync(),
      lenient: true,
    );
    return pubspec.environment['sdk']?.toString() ?? '-';
  } catch (_) {
    return '-';
  }
}

/// Gathers the full status row for one git repository.
Future<Map<String, String>> _auditRepo(
  Directory dir, {
  required String name,
  required String sdkConstraint,
  required bool sync,
}) async {
  await Process.run('git', ['fetch'], workingDirectory: dir.path);

  final remote =
      await _gitOrNull(dir.path, ['remote', 'get-url', 'origin']) ?? 'None';
  final branch = await _currentBranch(dir.path);
  final dirtyCount = await _dirtyCount(dir.path);
  final defBranch = await _defaultBranch(dir.path);
  final (:ahead, :behind) = await _aheadBehind(dir.path, defBranch);
  final lastDate = await _lastHumanCommitDate(dir.path);

  final statusStr = await _deriveStatus(
    dir.path,
    branch: branch,
    defBranch: defBranch,
    dirtyCount: dirtyCount,
    ahead: ahead,
    behind: behind,
    sync: sync,
  );

  return {
    'name': name,
    'path': dir.path,
    'remote': remote,
    'sdk': sdkConstraint,
    'date': lastDate,
    'status': statusStr,
  };
}

/// The current branch name, falling back to `HEAD` when detached or unset.
Future<String> _currentBranch(String repoPath) async {
  var branch = await _gitStdout(repoPath, ['branch', '--show-current']);
  if (branch.isEmpty) {
    branch = await _gitStdout(repoPath, ['rev-parse', '--abbrev-ref', 'HEAD']);
    if (branch.isEmpty) branch = 'HEAD';
  }
  return branch;
}

/// Runs git and returns trimmed stdout, or `null` on a non-zero exit.
Future<String?> _gitOrNull(String repoPath, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: repoPath);
  return result.exitCode == 0 ? result.stdout.toString().trim() : null;
}

/// Runs git and returns trimmed stdout regardless of exit code.
Future<String> _gitStdout(String repoPath, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: repoPath);
  return result.stdout.toString().trim();
}

/// Number of uncommitted entries reported by `git status --porcelain`.
Future<int> _dirtyCount(String repoPath) async {
  final status = await _gitStdout(repoPath, ['status', '--porcelain']);
  return status.split('\n').where((l) => l.isNotEmpty).length;
}

/// The remote default branch, falling back to `main` when unset.
Future<String> _defaultBranch(String repoPath) async {
  final symbolicRef = await _gitOrNull(repoPath, [
    'symbolic-ref',
    'refs/remotes/origin/HEAD',
  ]);
  return symbolicRef?.replaceAll('refs/remotes/origin/', '') ?? 'main';
}

/// Commits ahead of / behind `origin/[defBranch]`; zeros when unknown.
Future<({int ahead, int behind})> _aheadBehind(
  String repoPath,
  String defBranch,
) async {
  final counts = await _gitOrNull(repoPath, [
    'rev-list',
    '--left-right',
    '--count',
    'HEAD...origin/$defBranch',
  ]);
  final parts = counts?.split(RegExp(r'\s+'));
  if (parts == null || parts.length != 2) return (ahead: 0, behind: 0);
  return (
    ahead: int.tryParse(parts[0]) ?? 0,
    behind: int.tryParse(parts[1]) ?? 0,
  );
}

/// Date of the most recent commit not authored by dependabot, or `'N/A'`.
Future<String> _lastHumanCommitDate(String repoPath) async {
  final log = await _gitStdout(repoPath, [
    'log',
    '-n',
    '20',
    '--format=%ad|%an|%s',
    '--date=short',
  ]);
  for (final line in log.split('\n')) {
    final parts = line.split('|');
    if (parts.length >= 3 && !parts[1].toLowerCase().contains('dependabot')) {
      return parts[0];
    }
  }
  return 'N/A';
}

/// Derives the display status; when [sync] is set and the repo is cleanly
/// behind its default branch, attempts a fast-forward pull first.
Future<String> _deriveStatus(
  String repoPath, {
  required String branch,
  required String defBranch,
  required int dirtyCount,
  required int ahead,
  required int behind,
  required bool sync,
}) async {
  if (dirtyCount > 0) {
    var status = '🔴 Dirty ($dirtyCount uncommitted on $branch)';
    if (behind > 0) status += ', Behind by $behind';
    return status;
  }
  if (branch != defBranch) {
    var status = '🟡 Branch: $branch';
    if (ahead > 0) status += ' (Ahead by $ahead)';
    if (behind > 0) status += ' (Behind by $behind)';
    return status;
  }
  if (ahead > 0) return '🟡 Ahead by $ahead on $branch';
  if (behind > 0) {
    return sync && await _ffPull(repoPath)
        ? '🟢 Synced (+$behind commits to $branch)'
        : '⏳ Behind by $behind on $branch';
  }
  return '🟢 Clean (Up-to-date on $branch)';
}

/// Attempts `git pull --ff-only`; true on success.
Future<bool> _ffPull(String repoPath) async {
  final result = await Process.run('git', [
    'pull',
    '--ff-only',
  ], workingDirectory: repoPath);
  return result.exitCode == 0;
}

/// Sort key: dirty/behind first, then branches, then clean, then scratch;
/// ties broken by date descending.
int _compareRows(Map<String, String> a, Map<String, String> b) {
  final pA = _statusPriority(a['status']!);
  final pB = _statusPriority(b['status']!);
  if (pA != pB) return pA.compareTo(pB);
  return b['date']!.compareTo(a['date']!);
}

int _statusPriority(String status) {
  if (status.startsWith('🔴')) return 0;
  if (status.startsWith('⏳')) return 1;
  if (status.startsWith('🟡')) return 2;
  if (status.startsWith('🟢')) return 3;
  return 4;
}

/// Renders the audit rows as the markdown workspace report.
String _renderReport(List<Map<String, String>> rows) {
  final buffer = StringBuffer()
    ..writeln('# kevmoo Repositories & Workspace Layout')
    ..writeln()
    ..writeln('## Overview')
    ..writeln()
    ..writeln(
      '* **Scope**: Public repositories under [github.com/kevmoo](https://github.com/kevmoo) containing Dart code, alongside local development workspaces.',
    )
    ..writeln(
      '* **Workspace Organization**: Personal repositories are consolidated under [~/github/kevmoo](file:///usr/local/google/home/kevmoo/github/kevmoo).',
    )
    ..writeln()
    ..writeln('---')
    ..writeln()
    ..writeln('## Locally Synced Repositories')
    ..writeln()
    ..writeln(
      '| Local Directory | Remote Repository | SDK Constraint | Last Human Commit | Local Sync & Branch Status |',
    )
    ..writeln('| :--- | :--- | :--- | :--- | :--- |');

  for (final r in rows) {
    final name = r['name']!;
    final locLink = '[$name](file://${r['path']!})';
    final remLink = _remoteLink(r['remote']!, name);
    buffer.writeln(
      '| $locLink | $remLink | ${r['sdk']!} | ${r['date']!} | ${r['status']!} |',
    );
  }
  buffer.writeln();

  return buffer.toString();
}

/// Markdown link for the remote column; `'None'` passes through.
String _remoteLink(String remote, String name) {
  if (remote == 'None') return 'None';
  var cleanUrl = remote.replaceAll('git@github.com:', 'https://github.com/');
  if (cleanUrl.endsWith('.git')) {
    cleanUrl = cleanUrl.substring(0, cleanUrl.length - 4);
  }
  return '[kevmoo/$name]($cleanUrl)';
}
