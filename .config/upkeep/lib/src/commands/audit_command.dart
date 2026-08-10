import 'dart:io';

import 'package:args/command_runner.dart';

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

    final entities = targetDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final rows = <Map<String, String>>[];

    // Process repositories in parallel to fetch status faster
    final futures = <Future<void>>[];

    for (final dir in entities) {
      final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith('.') || name.startsWith('_')) continue;

      // SDK Constraint
      final pubspecFile = File('${dir.path}/pubspec.yaml');
      var sdkConstraint = '-';
      if (pubspecFile.existsSync()) {
        try {
          final content = pubspecFile.readAsStringSync();
          final match = RegExp(
            r'^\s*sdk:\s*[\x27"]?([^\x27"\r\n]+)[\x27"]?',
            multiLine: true,
          ).firstMatch(content);
          if (match != null) {
            sdkConstraint = match.group(1)!.trim();
          }
        } catch (_) {}
      }

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

      final fut = Future(() async {
        // Fetch remotes
        await Process.run('git', ['fetch'], workingDirectory: dir.path);

        final remoteResult = await Process.run('git', [
          'remote',
          'get-url',
          'origin',
        ], workingDirectory: dir.path);
        final remote = remoteResult.exitCode == 0
            ? remoteResult.stdout.toString().trim()
            : 'None';

        final branchResult = await Process.run('git', [
          'rev-parse',
          '--abbrev-ref',
          'HEAD',
        ], workingDirectory: dir.path);
        final branch = branchResult.stdout.toString().trim();

        final statusResult = await Process.run('git', [
          'status',
          '--porcelain',
        ], workingDirectory: dir.path);
        final dirtyLines = statusResult.stdout
            .toString()
            .trim()
            .split('\n')
            .where((l) => l.isNotEmpty)
            .toList();
        final isDirty = dirtyLines.isNotEmpty;

        final defBranchResult = await Process.run('git', [
          'symbolic-ref',
          'refs/remotes/origin/HEAD',
        ], workingDirectory: dir.path);
        var defBranch = 'main';
        if (defBranchResult.exitCode == 0) {
          defBranch = defBranchResult.stdout.toString().trim().replaceAll(
            'refs/remotes/origin/',
            '',
          );
        }

        final abResult = await Process.run('git', [
          'rev-list',
          '--left-right',
          '--count',
          'HEAD...origin/$defBranch',
        ], workingDirectory: dir.path);
        var ahead = 0;
        var behind = 0;
        if (abResult.exitCode == 0) {
          final parts = abResult.stdout.toString().trim().split(RegExp(r'\s+'));
          if (parts.length == 2) {
            ahead = int.tryParse(parts[0]) ?? 0;
            behind = int.tryParse(parts[1]) ?? 0;
          }
        }

        // Last human commit
        final logResult = await Process.run('git', [
          'log',
          '-n',
          '20',
          '--format=%ad|%an|%s',
          '--date=short',
        ], workingDirectory: dir.path);
        var lastDate = 'N/A';
        for (final line in logResult.stdout.toString().trim().split('\n')) {
          final parts = line.split('|');
          if (parts.length >= 3) {
            final author = parts[1].toLowerCase();
            if (!author.contains('dependabot')) {
              lastDate = parts[0];
              break;
            }
          }
        }

        final isDefault = (branch == defBranch);
        String statusStr;

        if (isDirty) {
          statusStr = '🔴 Dirty (${dirtyLines.length} uncommitted on $branch)';
          if (behind > 0) statusStr += ', Behind by $behind';
        } else if (!isDefault) {
          statusStr = '🟡 Branch: $branch';
          if (ahead > 0) statusStr += ' (Ahead by $ahead)';
          if (behind > 0) statusStr += ' (Behind by $behind)';
        } else if (ahead > 0) {
          statusStr = '🟡 Ahead by $ahead on $branch';
        } else if (behind > 0) {
          if (sync) {
            final pullResult = await Process.run('git', [
              'pull',
              '--ff-only',
            ], workingDirectory: dir.path);
            if (pullResult.exitCode == 0) {
              statusStr = '🟢 Synced (+$behind commits to $branch)';
            } else {
              statusStr = '⏳ Behind by $behind on $branch';
            }
          } else {
            statusStr = '⏳ Behind by $behind on $branch';
          }
        } else {
          statusStr = '🟢 Clean (Up-to-date on $branch)';
        }

        rows.add({
          'name': name,
          'path': dir.path,
          'remote': remote,
          'sdk': sdkConstraint,
          'date': lastDate,
          'status': statusStr,
        });
      });
      futures.add(fut);
    }

    await Future.wait(futures);

    // Sort rows: dirty/behind first, then branches, then by date descending
    rows.sort((a, b) {
      int priority(String s) {
        if (s.startsWith('🔴')) return 0;
        if (s.startsWith('⏳')) return 1;
        if (s.startsWith('🟡')) return 2;
        if (s.startsWith('🟢')) return 3;
        return 4;
      }

      final pA = priority(a['status']!);
      final pB = priority(b['status']!);
      if (pA != pB) return pA.compareTo(pB);
      return b['date']!.compareTo(a['date']!);
    });

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
      final path = r['path']!;
      final remote = r['remote']!;
      final sdk = r['sdk']!;
      final date = r['date']!;
      final status = r['status']!;

      final locLink = '[$name](file://$path)';
      var remLink = 'None';
      if (remote != 'None') {
        var cleanUrl = remote.replaceAll(
          'git@github.com:',
          'https://github.com/',
        );
        if (cleanUrl.endsWith('.git')) {
          cleanUrl = cleanUrl.substring(0, cleanUrl.length - 4);
        }
        remLink = '[kevmoo/$name]($cleanUrl)';
      }

      buffer.writeln('| $locLink | $remLink | $sdk | $date | $status |');
    }
    buffer.writeln();

    final output = buffer.toString();
    print(output);

    if (writeReadme) {
      final readmeFile = File('$targetPath/README.md');
      readmeFile.writeAsStringSync(output);
      stderr.writeln('Updated $targetPath/README.md');
    }
  }
}
