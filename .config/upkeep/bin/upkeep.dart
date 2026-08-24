import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:upkeep/upkeep.dart';

const version = '0.1.0';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'upkeep',
          'Cross-platform system status checker and updater.',
        )
        ..addCommand(AuditCommand())
        ..addCommand(CheckCommand())
        ..addCommand(UpdateCommand())
        ..addCommand(TriageCommand())
        ..addCommand(ListCommand());

  runner.argParser.addFlag(
    'version',
    negatable: false,
    help: 'Show version information.',
  );

  if (args.contains('--version')) {
    io.stdout.writeln('upkeep v$version');
    return;
  }

  if (args.isEmpty ||
      (!runner.commands.containsKey(args.first) &&
          args.first != '-h' &&
          args.first != '--help')) {
    args = ['check', ...args];
  }

  try {
    io.exitCode = await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    io.stderr.writeln(e);
    io.exitCode = 64;
  } catch (e) {
    io.stderr.writeln('Error: $e');
    io.exitCode = 1;
  }
}
