import 'dart:io';

import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:upkeep/src/models.dart';
import 'package:upkeep/src/upkeepers/gh_vault_upkeeper.dart';

void main() {
  group('GhVaultUpkeeper', () {
    late GhVaultUpkeeper upkeeper;

    setUp(() {
      upkeeper = GhVaultUpkeeper();
    });

    test('metadata', () {
      check(upkeeper.id).equals('gh_vault');
      check(upkeeper.displayName).equals('GitHub CLI Vault & Agent Safeguards');
    });

    test('isSupported returns true if ~/.config/gh_vault exists', () async {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      final exists = Directory(p.join(home, '.config', 'gh_vault'))
          .existsSync();
      check(await upkeeper.isSupported()).equals(exists);
    });

    test('check returns a valid UpkeepStatus', () async {
      if (!await upkeeper.isSupported()) return;

      final status = await upkeeper.check();
      check(status.upkeeperId).equals('gh_vault');
      check(status.state).anyOf([
        (s) => s.equals(UpkeepState.upToDate),
        (s) => s.equals(UpkeepState.outdated),
      ]);
    });
  });
}
