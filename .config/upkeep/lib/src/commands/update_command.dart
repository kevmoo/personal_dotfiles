import 'dart:io';

import 'package:args/command_runner.dart';

import '../runner.dart';
import '../ui/interactive_select.dart';
import '../ui/table_formatter.dart';

class UpdateCommand extends Command<void> {
  @override
  final String name = 'update';

  @override
  final String description =
      'Check status and apply updates for target or outdated upkeepers.';

  UpdateCommand() {
    argParser
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Automatically apply updates for all outdated items',
      )
      ..addMultiOption(
        'keeper',
        abbr: 'k',
        splitCommas: true,
        help: 'Target specific upkeeper(s) by ID',
      )
      ..addFlag(
        'verbose',
        negatable: false,
        help: 'Enable verbose command output during updates',
      )
      ..addFlag(
        'cleanup',
        negatable: false,
        help: 'Cleanup unmanaged packages during Brewfile sync',
      );
  }

  @override
  Future<void> run() async {
    final keepers = argResults!['keeper'] as List<String>;
    final positionals = argResults!.rest;
    final targets = [...keepers, ...positionals];

    final autoYes = argResults!['yes'] as bool;
    final verbose = argResults!['verbose'] as bool;
    final cleanup = argResults!['cleanup'] as bool;

    final upkeepRunner = UpkeepRunner();
    print('🔄 Checking system status across enabled upkeepers in parallel...');

    final statuses = await upkeepRunner.checkAll(targetIds: targets);

    if (statuses.isEmpty && targets.isNotEmpty) {
      print('❌ No matching upkeepers found for targets: ${targets.join(', ')}');
      exit(64);
    }

    print(TableFormatter.formatStatusTable(statuses));

    final outdated = statuses.where((s) => s.isOutdated).toList();

    List<String> toUpdate;
    if (targets.isNotEmpty) {
      toUpdate = statuses.map((s) => s.upkeeperId).toList();
    } else if (outdated.isEmpty) {
      print('✨ Everything is up to date! No updates required.');
      return;
    } else if (autoYes) {
      toUpdate = outdated.map((s) => s.upkeeperId).toList();
    } else {
      toUpdate = InteractiveSelect.promptSelection(outdated);
    }

    if (toUpdate.isEmpty) {
      print('⏭️  Skipped updates.');
      return;
    }

    print(
      '\n🚀 Applying updates for selected subsystems: ${toUpdate.join(', ')}...\n',
    );
    final updateResults = await upkeepRunner.updateSelected(
      toUpdate,
      verbose: verbose,
      cleanup: cleanup,
    );

    print('\n═══ Update Execution Results ═══\n');
    for (final res in updateResults) {
      final icon = res.success ? '✅' : '❌';
      print('$icon ${res.displayName}: ${res.message}');
      if (res.errorMessage != null && res.errorMessage!.isNotEmpty) {
        print('   Error: ${res.errorMessage}');
      }
    }

    print('\n✨ System upkeep run completed.');
  }
}
