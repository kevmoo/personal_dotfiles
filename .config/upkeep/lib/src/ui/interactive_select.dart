import 'dart:io';

import '../models.dart';

class InteractiveSelect {
  /// Prompts user to select which outdated upkeepers to run updates for.
  static List<String> promptSelection(List<UpkeepStatus> outdatedStatuses) {
    if (outdatedStatuses.isEmpty) return [];

    // If non-interactive stdin, return empty unless forced
    if (!stdioType(stdin).name.contains('terminal') &&
        stdin.hasTerminal == false) {
      return outdatedStatuses.map((s) => s.upkeeperId).toList();
    }

    print('\x1B[1m\x1B[36m📦 Outdated Subsystems Detected:\x1B[0m');
    for (var i = 0; i < outdatedStatuses.length; i++) {
      final s = outdatedStatuses[i];
      print('  [\x1B[33m${i + 1}\x1B[0m] ${s.displayName} (${s.summary})');
    }
    print('  [\x1B[32ma\x1B[0m] Select All Outdated');
    print('  [\x1B[31mq\x1B[0m] Quit / Skip Updates');
    print('');

    stdout.write('Enter choices (e.g. 1,2 or a/q) [default: a]: ');
    final input = stdin.readLineSync()?.trim().toLowerCase() ?? 'a';

    if (input == 'q') return [];
    if (input == 'a' || input.isEmpty) {
      return outdatedStatuses.map((s) => s.upkeeperId).toList();
    }

    final selectedIds = <String>{};
    final parts = input.split(RegExp(r'[, ]+'));

    for (final part in parts) {
      final idx = int.tryParse(part);
      if (idx != null && idx >= 1 && idx <= outdatedStatuses.length) {
        selectedIds.add(outdatedStatuses[idx - 1].upkeeperId);
      }
    }

    return selectedIds.toList();
  }
}
