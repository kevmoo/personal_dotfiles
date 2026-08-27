import 'dart:io';

import 'package:args/args.dart';
import 'package:gh_vault/gh_vault.dart';

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'runtime-dir',
      abbr: 'r',
      help: 'Custom runtime directory for lease cleanup (for testing/dry-run).',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.');

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('Usage: gh-lock [options]\n');
    print(parser.usage);
    exit(0);
  }

  final customRuntimeDir = results['runtime-dir'] as String?;
  final revoked = AdminLease.revoke(customBaseDir: customRuntimeDir);

  if (revoked) {
    print(
      '🔒 Admin token lease revoked. '
      'GitHub CLI returned to restricted baseline mode.',
    );
  } else {
    print(
      '🔒 GitHub CLI is already in restricted baseline mode '
      '(no active lease).',
    );
  }
}
