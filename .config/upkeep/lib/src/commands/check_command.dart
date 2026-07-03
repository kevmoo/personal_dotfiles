import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../runner.dart';
import '../ui/table_formatter.dart';
import '../upkeepers/brewfile_upkeeper.dart';

class CheckCommand extends Command<void> {
  @override
  final String name = 'check';

  @override
  final String description =
      'Perform a non-destructive status check across upkeepers.';

  CheckCommand() {
    argParser
      ..addMultiOption(
        'keeper',
        abbr: 'k',
        splitCommas: true,
        help: 'Target specific upkeeper(s) by ID',
      )
      ..addFlag('json', negatable: false, help: 'Output status report as JSON')
      ..addFlag(
        'interactive',
        abbr: 'i',
        negatable: false,
        help: 'Interactively triage Brewfile discrepancies',
      );
  }

  @override
  Future<void> run() async {
    final keepers = argResults!['keeper'] as List<String>;
    final positionals = argResults!.rest;
    final targets = [...keepers, ...positionals];

    final isJson = argResults!['json'] as bool;

    final upkeepRunner = UpkeepRunner();
    if (!isJson) {
      print(
        '🔄 Checking system status across enabled upkeepers in parallel...',
      );
    }

    final statuses = await upkeepRunner.checkAll(targetIds: targets);

    if (statuses.isEmpty && targets.isNotEmpty) {
      print('❌ No matching upkeepers found for targets: ${targets.join(', ')}');
      exit(64);
    }

    if (isJson) {
      final payload = {
        'version': '0.1.0',
        'hostname': Platform.localHostname,
        'platform': Platform.operatingSystem,
        'upkeepers': statuses.map((s) => s.toJson()).toList(),
      };
      print(const JsonEncoder.withIndent('  ').convert(payload));
      return;
    }

    print(TableFormatter.formatStatusTable(statuses));

    final isInteractive = argResults!['interactive'] as bool;

    if (isInteractive) {
      final brewfileUpkeeper = BrewfileUpkeeper();
      await brewfileUpkeeper.triageInteractive();
      return;
    }

    final outdated = statuses.where((s) => s.isOutdated).toList();
    if (outdated.isEmpty) {
      print('✨ Everything is up to date! No updates required.');
    } else {
      print(
        'ℹ️  Check mode active. ${outdated.length} item(s) available for update.',
      );
      if (statuses.any((s) => s.upkeeperId == 'brewfile' && s.isOutdated)) {
        print(
          '💡 Tip: Run "upkeep check -i" (or "upkeep triage") to interactively manage Brewfile packages.',
        );
      }
    }
  }
}
