import 'dart:io';

import 'package:args/args.dart';
import 'package:gh_vault/gh_vault.dart';

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
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.');

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('Usage: gh-unlock [options]\n');
    print(parser.usage);
    exit(0);
  }

  final minutes = int.tryParse(results['minutes'] as String) ?? 5;
  final vaultPath =
      results['vault-file'] as String? ?? VaultPaths.defaultVaultFile;
  final customRuntimeDir = results['runtime-dir'] as String?;

  final vaultFile = File(vaultPath);
  if (!vaultFile.existsSync()) {
    stderr.writeln('❌ Vault token not found at $vaultPath');
    stderr.writeln('   Initialize root vault with:');
    stderr.writeln('     sudo install -d -m 0700 /etc/github');
    stderr.writeln(
      '     sudo install -m 0600 /dev/null ${VaultPaths.defaultVaultFile}',
    );
    stderr.writeln('     sudo tee ${VaultPaths.defaultVaultFile} > /dev/null');
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
