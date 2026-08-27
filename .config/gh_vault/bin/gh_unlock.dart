import 'dart:io';

import 'package:args/args.dart';
import 'package:gh_vault/gh_vault.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'minutes',
      abbr: 'm',
      defaultsTo: '5',
      help: 'Duration of admin lease in minutes.',
    )
    ..addOption(
      'vault-file',
      abbr: 'v',
      help: 'Path to custom admin token vault file (for testing/dry-run).',
    )
    ..addOption(
      'runtime-dir',
      abbr: 'r',
      help: 'Custom runtime directory for storing the lease (for testing/dry-run).',
    )
    ..addFlag(
      'init',
      abbr: 'i',
      negatable: false,
      help: 'Initialize the root vault token at /etc/github/admin.token interactively.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.');

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('Usage: gh-unlock [minutes] [options]\n');
    print(parser.usage);
    exit(0);
  }

  final vaultPath =
      results['vault-file'] as String? ?? VaultPaths.defaultVaultFile;

  if (results['init'] as bool) {
    stdout.write('Enter Admin GitHub Token: ');
    final hasTerm = stdin.hasTerminal;
    if (hasTerm) stdin.echoMode = false;
    final String token;
    try {
      token = stdin.readLineSync()?.trim() ?? '';
    } finally {
      if (hasTerm) stdin.echoMode = true;
    }
    stdout.writeln();

    if (token.isEmpty) {
      stderr.writeln('❌ Error: Empty token provided.');
      exit(1);
    }

    final vaultDir = Directory(p.dirname(vaultPath));
    if (!vaultDir.existsSync()) {
      vaultDir.createSync(recursive: true);
      Process.runSync('chmod', ['0700', vaultDir.path]);
    }

    final vaultFile = File(vaultPath);
    vaultFile.writeAsStringSync(token, flush: true);
    Process.runSync('chmod', ['0600', vaultFile.path]);

    print('✅ Root vault successfully initialized at $vaultPath (0600).');
    exit(0);
  }

  final rawMinutes = results.rest.isNotEmpty
      ? results.rest.first
      : (results['minutes'] as String);
  final minutes = int.tryParse(rawMinutes) ?? 5;
  final customRuntimeDir = results['runtime-dir'] as String?;

  final vaultFile = File(vaultPath);
  if (!vaultFile.existsSync()) {
    stderr.writeln('❌ Vault token not found at $vaultPath');
    stderr.writeln('   Initialize root vault with:');
    stderr.writeln('     sudo gh-unlock --init');
    exit(1);
  }

  final token = vaultFile.readAsStringSync().trim();
  if (token.isEmpty) {
    stderr.writeln('❌ Vault token file at $vaultPath is empty.');
    exit(1);
  }

  final sudoUser = Platform.environment['SUDO_USER'];
  int? targetUid;
  if (sudoUser != null && sudoUser.isNotEmpty) {
    final res = Process.runSync('id', ['-u', sudoUser]);
    targetUid = int.tryParse(res.stdout.toString().trim());
  }

  AdminLease.write(
    token: token,
    duration: Duration(minutes: minutes),
    targetUid: targetUid,
    customBaseDir: customRuntimeDir,
  );

  final expiry = DateTime.now().add(Duration(minutes: minutes));
  final timeStr =
      '${expiry.hour.toString().padLeft(2, '0')}:'
      '${expiry.minute.toString().padLeft(2, '0')}:'
      '${expiry.second.toString().padLeft(2, '0')}';
  print(
    '🔓 GitHub CLI elevated with admin privileges for $minutes minutes '
    '(expires at $timeStr).',
  );
}
