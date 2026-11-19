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
        check(table).not(.it()..contains('Command: upkeep update'));
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
          check(table).not(.it()..contains('Command:'));
        });
      },
    );

    test(
      'prints details and concise error message once when status is error',
      () {
        const status = UpkeepStatus(
          upkeeperId: 'dotfiles-corp',
          displayName: 'Private Corp Dotfiles Repository',
          state: UpkeepState.error,
          summary: 'Private dotfiles hook check failed',
          details: [
            'OK: rules/style.md',
            'ANCHOR_CONFLICT: SKILL.md missing anchor',
          ],
          errorMessage: 'Hook exited with code 20',
        );

        final table = TableFormatter.formatStatusTable([status]);
        check(table).contains('🔴 Private Corp Dotfiles Repository');
        check(table).contains('• OK: rules/style.md');
        check(table).contains('• ANCHOR_CONFLICT: SKILL.md missing anchor');
        check(table).contains('❌ Error: Hook exited with code 20');
        check(RegExp(RegExp.escape('OK: rules/style.md')).allMatches(table))
            .length
            .equals(1);
        check(
          RegExp(RegExp.escape('ANCHOR_CONFLICT: SKILL.md missing anchor'))
              .allMatches(table),
        ).length.equals(1);
      },
    );
  });
}
