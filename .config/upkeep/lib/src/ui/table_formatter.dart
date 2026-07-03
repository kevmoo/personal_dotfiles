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
    const cyan = '\x1B[36m';
    const green = '\x1B[32m';
    const yellow = '\x1B[33m';
    const red = '\x1B[31m';
    const reset = '\x1B[0m';

    switch (state) {
      case UpkeepState.upToDate:
        return '${green}Up to date$reset';
      case UpkeepState.outdated:
        return '${yellow}Outdated / Action Required$reset';
      case UpkeepState.error:
        return '${red}Error$reset';
      case UpkeepState.skipped:
        return '${cyan}Skipped$reset';
    }
  }
}
