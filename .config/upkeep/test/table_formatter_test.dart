import 'package:checks/checks.dart';
import 'package:io/ansi.dart';
import 'package:test/test.dart';
import 'package:upkeep/upkeep.dart';

void main() {
  group('TableFormatter Output', () {
    test(
      'prints update command when subsystem status is outdated (yellow)',
      () {
        overrideAnsiOutput(true, () {
          final status = UpkeepStatus(
            upkeeperId: 'brew',
            displayName: 'Homebrew Package Upgrades',
            state: UpkeepState.outdated,
            summary: '1 formula outdated',
          );

          final expectedCmd = wrapWith('upkeep update brew', [styleBold, blue]);
          final table = TableFormatter.formatStatusTable([status]);
          check(table).contains('Command: $expectedCmd');
        });
      },
    );

    test(
      'does not print update command when subsystem status is upToDate (green)',
      () {
        final status = UpkeepStatus(
          upkeeperId: 'brew',
          displayName: 'Homebrew Package Upgrades',
          state: UpkeepState.upToDate,
          summary: 'Up to date',
        );

        final table = TableFormatter.formatStatusTable([status]);
        check(table).not((c) => c.contains('Command: upkeep update'));
      },
    );

    test(
      'prints action hint without update command when status is needsTriage',
      () {
        overrideAnsiOutput(true, () {
          const status = UpkeepStatus(
            upkeeperId: 'brewfile',
            displayName: 'Homebrew Brewfile Sync',
            state: UpkeepState.needsTriage,
            summary: '1 unmanaged in Brewfile',
            details: ['Unmanaged formula: ffmpeg'],
            actionHint: 'upkeep triage',
          );

          final expectedHint = wrapWith('upkeep triage', [styleBold, blue]);
          final table = TableFormatter.formatStatusTable([status]);
          check(table).contains('🔵 Homebrew Brewfile Sync');
          check(table).contains('FYI / Needs Triage');
          check(table).contains('Action:  $expectedHint');
          check(table).not((c) => c.contains('Command:'));
        });
      },
    );
  });
}
