import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:upkeep/upkeep.dart';

const version = '0.1.0';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<void>(
          'upkeep',
          'Cross-platform system status checker and updater.',
        )
        ..addCommand(CheckCommand())
        ..addCommand(UpdateCommand())
        ..addCommand(ListCommand());

  runner.argParser.addFlag(
    'version',
    negatable: false,
    help: 'Show version information.',
  );

  if (args.contains('--version')) {
    print('upkeep v$version');
    exit(0);
  }

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
