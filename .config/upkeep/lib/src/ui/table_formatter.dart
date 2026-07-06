import 'package:io/ansi.dart';

import '../models.dart';

class TableFormatter {
  static String formatStatusTable(List<UpkeepStatus> statuses) {
    final buffer = StringBuffer();
    buffer.writeln('\n═══ System Upkeep Status Audit ═══\n');

    for (final s in statuses) {
      final icon = _statusIcon(s.state);
      final badge = _statusBadge(s.state);
      buffer.writeln('$icon ${s.displayName}');
      buffer.writeln('   State:   $badge');
      buffer.writeln('   Summary: ${s.summary}');
      if (s.isOutdated) {
        final formattedCmd = wrapWith('upkeep update ${s.upkeeperId}', [
          styleBold,
          blue,
        ]);
        buffer.writeln('   Command: $formattedCmd');
      }

      if (s.details.isNotEmpty) {
        for (final d in s.details) {
          buffer.writeln('     • $d');
        }
      }
      if (s.errorMessage != null) {
        buffer.writeln('     ❌ Error: ${s.errorMessage}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  static String _statusIcon(UpkeepState state) {
    switch (state) {
      case UpkeepState.upToDate:
        return '🟢';
      case UpkeepState.outdated:
        return '🟡';
      case UpkeepState.error:
        return '🔴';
      case UpkeepState.skipped:
        return '⚪';
    }
  }

  static String _statusBadge(UpkeepState state) {
    switch (state) {
      case UpkeepState.upToDate:
        return green.wrap('Up to date')!;
      case UpkeepState.outdated:
        return yellow.wrap('Outdated / Action Required')!;
      case UpkeepState.error:
        return red.wrap('Error')!;
      case UpkeepState.skipped:
        return cyan.wrap('Skipped')!;
    }
  }
}
