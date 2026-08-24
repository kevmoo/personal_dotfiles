import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

Future<void> _git(String repoDir, List<String> args) async {
  final result = await Process.run('git', [
    '-c',
    'user.email=test@example.com',
    '-c',
    'user.name=Test',
    ...args,
  ], workingDirectory: repoDir);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
}

void main() {
  group('AuditCommand fixture audit', () {
    late Directory target;
    late List<String> printed;

    setUp(() async {
      target = await Directory.systemTemp.createTemp('upkeep_audit_test');
      printed = [];

      // 1. Plain directory without .git -> "Local scratch".
      Directory(p.join(target.path, 'scratch_dir')).createSync();

      // 2. Clean repo on main with an SDK constraint in pubspec.yaml.
      final clean = Directory(p.join(target.path, 'clean_repo'))..createSync();
      File(p.join(clean.path, 'pubspec.yaml'))
          .writeAsStringSync('name: clean_repo\nenvironment:\n  sdk: ^3.0.0\n');
      await _git(clean.path, ['init', '-b', 'main']);
      await _git(clean.path, ['add', '.']);
      await _git(clean.path, ['commit', '-m', 'init']);

      // 3. Repo with uncommitted changes -> "Dirty". Its pubspec has no
      // environment block; the only `sdk:` line is the flutter dependency,
      // which naive line matching would misreport as the SDK constraint.
      final dirty = Directory(p.join(target.path, 'dirty_repo'))..createSync();
      File(p.join(dirty.path, 'pubspec.yaml')).writeAsStringSync(
        'name: dirty_repo\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      File(p.join(dirty.path, 'a.txt')).writeAsStringSync('committed\n');
      await _git(dirty.path, ['init', '-b', 'main']);
      await _git(dirty.path, ['add', '.']);
      await _git(dirty.path, ['commit', '-m', 'init']);
      File(p.join(dirty.path, 'b.txt')).writeAsStringSync('uncommitted\n');

      // 4. Dot-prefixed directory must be skipped entirely.
      Directory(p.join(target.path, '.hidden')).createSync();
    });

    tearDown(() async {
      await target.delete(recursive: true);
    });

    Future<String> runAudit() async {
      final runner = CommandRunner<int>('upkeep', 'test')
        ..addCommand(AuditCommand());
      await runZoned(
        () => runner.run(['audit', target.path]),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );
      return printed.join('\n');
    }

    test('renders statuses, SDK constraints, sorting, and skips', () async {
      final output = await runAudit();

      // Markdown scaffolding.
      check(output).contains('## Locally Synced Repositories');
      check(output).contains('| Local Directory | Remote Repository |');

      // Row statuses.
      check(output).contains('⚪ Local scratch (No .git repo)');
      check(output).contains('🟢 Clean (Up-to-date on main)');
      check(output).contains('🔴 Dirty (1 uncommitted on main)');

      // SDK constraint parsed from pubspec.yaml; repos without one get '-'.
      check(output).contains('^3.0.0');

      // A `sdk: flutter` dependency line must not masquerade as the
      // environment SDK constraint.
      check(output).not((it) => it.contains('| flutter |'));

      // No remotes configured -> remote column renders 'None'.
      check(output).contains('| None |');

      // Dot-prefixed directories are skipped.
      check(output).not((it) => it.contains('.hidden'));

      // Sort order: dirty first, then clean, then scratch.
      final dirtyIdx = output.indexOf('dirty_repo');
      final cleanIdx = output.indexOf('clean_repo');
      final scratchIdx = output.indexOf('scratch_dir');
      check(dirtyIdx).isGreaterThan(-1);
      check(cleanIdx).isGreaterThan(dirtyIdx);
      check(scratchIdx).isGreaterThan(cleanIdx);
    });

    test('exits with code 1 for a missing target directory', () async {
      final runner = CommandRunner<int>('upkeep', 'test')
        ..addCommand(AuditCommand());
      final missing = p.join(target.path, 'does_not_exist');
      final code = await runner.run(['audit', missing]);
      check(code).equals(1);
    });
  });
}
