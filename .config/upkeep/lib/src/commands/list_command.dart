import 'dart:convert';

import 'package:args/command_runner.dart';

import '../runner.dart';

class ListCommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description =
      'List all registered upkeepers and their platform support status.';

  ListCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Output list report as JSON',
    );
  }

  @override
  Future<int> run() async {
    final isJson = argResults!['json'] as bool;
    final upkeepRunner = UpkeepRunner();

    final adapterList = <Map<String, dynamic>>[];
    for (final u in upkeepRunner.upkeepers) {
      final supported = await u.isSupported();
      adapterList.add({
        'id': u.id,
        'displayName': u.displayName,
        'supported': supported,
      });
    }

    if (isJson) {
      print(
        const JsonEncoder.withIndent('  ').convert({'upkeepers': adapterList}),
      );
      return 0;
    }

    print('═══ Registered System Upkeepers ═══\n');
    for (final adapter in adapterList) {
      final statusIcon = adapter['supported'] as bool
          ? '🟢 Supported'
          : '⚪ Unsupported';
      final id = (adapter['id'] as String).padRight(15);
      final name = adapter['displayName'] as String;
      print(' • $id  $name ($statusIcon)');
    }
    return 0;
  }
}
