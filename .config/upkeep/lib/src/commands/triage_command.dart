import 'package:args/command_runner.dart';

import '../upkeepers/brewfile_upkeeper.dart';

class TriageCommand extends Command<void> {
  @override
  final String name = 'triage';

  @override
  final String description =
      'Interactively triage Brewfile discrepancies (unmanaged or missing packages).';

  @override
  Future<void> run() async {
    final brewfileUpkeeper = BrewfileUpkeeper();
    await brewfileUpkeeper.triageInteractive();
  }
}
