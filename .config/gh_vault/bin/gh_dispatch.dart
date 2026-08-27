import 'dart:io';

import 'package:gh_vault/gh_vault.dart';

Future<void> main(List<String> args) async {
  final lease = AdminLease.readActive();
  final environment = Map<String, String>.from(Platform.environment);

  if (lease != null) {
    environment['GH_TOKEN'] = lease.token;
  }

  final executable = VaultPaths.resolveRealGhExecutable();
  if (executable == null) {
    stderr.writeln('❌ gh_vault: Could not find upstream gh binary in PATH.');
    exit(127);
  }

  try {
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await process.exitCode;
    exit(exitCode);
  } on ProcessException catch (e) {
    stderr.writeln('❌ gh_vault execution failed: ${e.message}');
    exit(127);
  }
}
