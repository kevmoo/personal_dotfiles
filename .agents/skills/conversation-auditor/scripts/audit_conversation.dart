import 'dart:convert';
import 'dart:io';

final RegExp _systemTagsRegex = RegExp(
  r'(?:<memory>[\s\S]*?<\/memory>'
  r'|<ADDITIONAL_METADATA>[\s\S]*?<\/ADDITIONAL_METADATA>'
  r'|<SYSTEM_MESSAGE>[\s\S]*?<\/SYSTEM_MESSAGE>'
  r'|<CONTEXT_SUMMARY>[\s\S]*?<\/CONTEXT_SUMMARY>'
  r'|<\/?USER_REQUEST>)',
  multiLine: true,
);

final RegExp _whitespaceRegex = RegExp(r'\s+');
final RegExp _pbtxtTitleRegex = RegExp(r'title:\s*"((?:[^"\\]|\\.)*)"');

/// Strips ambient `<memory>`, `<ADDITIONAL_METADATA>`, `<SYSTEM_MESSAGE>`,
/// `<CONTEXT_SUMMARY>`, and `<USER_REQUEST>` wrapper tags.
String stripSystemTags(String text) {
  if (text.isEmpty) return '';
  return text.replaceAll(_systemTagsRegex, '').trim();
}

/// Truncates the middle of [text], preserving [head] leading chars and [tail]
/// trailing chars.
String truncateMiddle(String text, {int head = 400, int tail = 400}) {
  final clean = text.replaceAll(_whitespaceRegex, ' ').trim();
  if (clean.length <= head + tail) {
    return clean;
  }
  final omitted = clean.length - head - tail;
  return '${clean.substring(0, head)} ... [$omitted chars omitted] ... '
      '${clean.substring(clean.length - tail)}';
}

/// Reads the conversation title directly from `~/.gemini/jetski/annotations/<cid>.pbtxt`.
String readAnnotationTitle(String appDataDir, String cid) {
  final pbtxtFile = File('$appDataDir/annotations/$cid.pbtxt');
  if (!pbtxtFile.existsSync()) return '';
  try {
    final content = pbtxtFile.readAsStringSync();
    final match = _pbtxtTitleRegex.firstMatch(content);
    if (match != null) {
      return match.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
  } catch (_) {}
  return '';
}

/// Fast header check inspecting the first 64 KB of `transcript.jsonl` for
/// `<subagent_reminder>` or `"is_subagent": true`.
bool isSubagentJsonlFallback(File transcriptFile) {
  RandomAccessFile? raf;
  try {
    raf = transcriptFile.openSync(mode: FileMode.read);
    final bytes = raf.readSync(65536);
    final headChunk = utf8.decode(bytes, allowMalformed: true);
    return headChunk.contains('<subagent_reminder>') ||
        headChunk.contains('"is_subagent": true') ||
        headChunk.contains('"is_subagent":true');
  } catch (_) {
    return false;
  } finally {
    raf?.closeSync();
  }
}

class _AuditCliConfig {
  String appDataDir;
  final List<String> targetConvos = [];
  String extractPrompts = 'first';
  bool includeSubagents = false;
  int requestedLastN = 0;

  _AuditCliConfig({required this.appDataDir});
}

_AuditCliConfig _parseAuditCliArgs(List<String> args) {
  final home = Platform.environment['HOME'] ?? '/tmp';
  var appDataDir = '$home/.gemini/jetski';
  var startIndex = 0;
  if (!args[0].startsWith('--') && Directory(args[0]).existsSync()) {
    appDataDir = args[0];
    startIndex = 1;
  }

  final cfg = _AuditCliConfig(appDataDir: appDataDir);
  for (var i = startIndex; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--last' && i + 1 < args.length) {
      cfg.requestedLastN = int.tryParse(args[++i]) ?? 1;
    } else if (arg == '--prompts' && i + 1 < args.length) {
      cfg.extractPrompts = args[++i];
    } else if (arg == '--include-subagents') {
      cfg.includeSubagents = true;
    } else {
      cfg.targetConvos.add(arg);
    }
  }
  return cfg;
}

class _AuditReportState {
  final Map<String, int> toolCounts = {};
  final Map<String, Map<String, dynamic>> commandTracker = {};
  final List<Map<String, dynamic>> largeSteps = [];
  final Map<String, Map<String, dynamic>> sequenceTracker = {};
  final Map<String, List<String>> userPrompts = {};
  final Map<String, int> stats = {
    'totalSteps': 0,
    'totalToolCalls': 0,
    'totalPromptsExtracted': 0,
  };
}

void _printAuditReport(
  _AuditCliConfig cfg,
  List<String> targetConvos,
  _AuditReportState state,
) {
  print(
    '--- Aggregated Audit Report for ${targetConvos.length} Conversation(s) ---',
  );
  print('Conversations analyzed: ${targetConvos.join(', ')}');
  print('');
  print('📊 Audit Metadata Summary:');
  print('  - Total Steps (JSONL lines) parsed: ${state.stats['totalSteps']}');
  print('  - Total Tool Calls analyzed: ${state.stats['totalToolCalls']}');
  print(
    '  - Total User Prompts extracted: ${state.stats['totalPromptsExtracted']}',
  );
  print('  - Prompt Extraction Mode: ${cfg.extractPrompts}');
  print('  - Include Subagents: ${cfg.includeSubagents}');

  print('\n1. Tool Usage Frequencies:');
  final sortedTools = state.toolCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sortedTools) {
    print('  - ${entry.key}: ${entry.value}');
  }

  print(
    '\n2. Repeated Tool Sequences (3+ consecutive calls, potential for bulk operations or new MCP):',
  );
  final sortedSeqs = state.sequenceTracker.entries.toList()
    ..sort(
      (a, b) =>
          (b.value['instances'] as int).compareTo(a.value['instances'] as int),
    );
  for (final entry in sortedSeqs) {
    final instances = entry.value['instances'];
    final convoCount = (entry.value['convos'] as Set<String>).length;
    print('  - ${entry.key}: $instances sequences across $convoCount convos');
  }

  print('\n3. Shell Commands Executed (Potential for scripting):');
  final sortedCmds = state.commandTracker.entries.toList()
    ..sort(
      (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int),
    );
  for (final entry in sortedCmds.take(15)) {
    final total = entry.value['total'];
    final convoCount = (entry.value['convos'] as Set<String>).length;
    final repoCount = (entry.value['repos'] as Set<String>).length;
    final cmdDisplay = truncateMiddle(entry.key, head: 120, tail: 120);
    print(
      '  - [${total}x] $cmdDisplay (across $convoCount convo(s), $repoCount repo(s))',
    );
  }

  print('\n4. Largest Context Hogs (Effective Content > 10,000 chars):');
  state.largeSteps.sort(
    (a, b) => (b['length'] as int).compareTo(a['length'] as int),
  );
  for (final ls in state.largeSteps.take(5)) {
    print(
      '  - Step ${ls['step']} in convo ${ls['convo']} (${ls['type']} from ${ls['source']}): ${ls['length']} characters',
    );
  }

  _printExtractedPrompts(cfg, targetConvos, state.userPrompts);
}

void _printExtractedPrompts(
  _AuditCliConfig cfg,
  List<String> targetConvos,
  Map<String, List<String>> userPrompts,
) {
  if (cfg.extractPrompts == 'none' || userPrompts.isEmpty) return;
  print('\n5. Distinct Tasks Performed (User Prompts):');
  for (final convoId in targetConvos) {
    final prompts = userPrompts[convoId];
    if (prompts == null) continue;
    final title = readAnnotationTitle(cfg.appDataDir, convoId);
    final titleSuffix = title.isNotEmpty ? ' ("$title")' : '';
    print('  - Convo $convoId$titleSuffix:');
    for (final prompt in prompts) {
      final cleanPrompt = truncateMiddle(prompt, head: 400, tail: 400);
      print('      * "$cleanPrompt"');
    }
  }
}

void main(List<String> args) async {
  if (args.isEmpty) {
    print(
      'Usage: dart run audit_conversation.dart [<app_data_dir>] [convo_id1 ...] '
      '[--last N] [--prompts all|first|none] [--include-subagents]',
    );
    exit(1);
  }

  final cfg = _parseAuditCliArgs(args);
  final countToFetch = cfg.requestedLastN > 0
      ? cfg.requestedLastN
      : (cfg.targetConvos.isEmpty ? 1 : 0);
  if (countToFetch > 0) {
    cfg.targetConvos.addAll(
      getLastNConversations(
        cfg.appDataDir,
        countToFetch,
        includeSubagents: cfg.includeSubagents,
      ),
    );
  }

  final targetConvos = cfg.targetConvos.toSet().toList();
  if (targetConvos.isEmpty) {
    print('No conversations found to audit.');
    return;
  }

  final state = _AuditReportState();
  for (final convoId in targetConvos) {
    await auditSingleTranscript(
      cfg.appDataDir,
      convoId,
      state.toolCounts,
      state.commandTracker,
      state.largeSteps,
      state.sequenceTracker,
      state.userPrompts,
      cfg.extractPrompts,
      state.stats,
    );
  }

  _printAuditReport(cfg, targetConvos, state);
}

List<String> getLastNConversations(
  String appDataDir,
  int n, {
  bool includeSubagents = false,
}) {
  final brainDir = Directory('$appDataDir/brain');
  if (!brainDir.existsSync()) return [];

  final convos = <Map<String, dynamic>>[];
  for (final entity in brainDir.listSync()) {
    if (entity is! Directory) continue;
    final transcript = File(
      '${entity.path}/.system_generated/logs/transcript.jsonl',
    );
    if (!transcript.existsSync()) continue;
    if (!includeSubagents && isSubagentJsonlFallback(transcript)) continue;
    final id = entity.uri.pathSegments.lastWhere((e) => e.isNotEmpty);
    convos.add({'id': id, 'modified': transcript.statSync().modified});
  }

  convos.sort(
    (a, b) => (b['modified'] as DateTime).compareTo(a['modified'] as DateTime),
  );
  return convos.take(n).map((e) => e['id'] as String).toList();
}

String _resolveToolName(Map<dynamic, dynamic> tc) {
  dynamic toolNameRaw = tc['name'];
  final fn = tc['function'];
  if (toolNameRaw == null && fn is Map) {
    toolNameRaw = fn['name'];
  }
  if (toolNameRaw is Map && toolNameRaw.containsKey('name')) {
    return toolNameRaw['name'].toString();
  }
  return toolNameRaw?.toString() ?? tc.toString();
}

Map<dynamic, dynamic>? _resolveToolArgsMap(Map<dynamic, dynamic> tc) {
  dynamic argsData = tc['args'] ?? tc['arguments'];
  final fn = tc['function'];
  if (argsData == null && fn is Map) {
    argsData = fn['arguments'];
  }
  if (argsData is String) {
    try {
      argsData = jsonDecode(argsData);
    } catch (_) {
      return null;
    }
  }
  return argsData is Map ? argsData : null;
}

void _recordShellCommand(
  Map<dynamic, dynamic> tc,
  String convoId,
  Map<String, Map<String, dynamic>> commandTracker,
) {
  final argsMap = _resolveToolArgsMap(tc);
  if (argsMap == null) return;

  dynamic cmd =
      argsMap['CommandLine'] ?? argsMap['command_line'] ?? argsMap['command'];
  if (cmd == null) return;

  if (cmd is String && cmd.startsWith('"') && cmd.endsWith('"')) {
    try {
      cmd = jsonDecode(cmd);
    } catch (_) {}
  }

  final cmdStr = cmd.toString();
  final repo = argsMap['Cwd']?.toString() ?? 'unknown';
  final entry = commandTracker.putIfAbsent(
    cmdStr,
    () => {'total': 0, 'convos': <String>{}, 'repos': <String>{}},
  );
  entry['total'] = (entry['total'] as int) + 1;
  (entry['convos'] as Set<String>).add(convoId);
  (entry['repos'] as Set<String>).add(repo);
}

void _recordSequence(
  String? toolName,
  int count,
  String convoId,
  Map<String, Map<String, dynamic>> sequenceTracker,
) {
  if (toolName == null || count <= 2) return;
  final entry = sequenceTracker.putIfAbsent(
    toolName,
    () => {'instances': 0, 'convos': <String>{}},
  );
  entry['instances'] = (entry['instances'] as int) + 1;
  (entry['convos'] as Set<String>).add(convoId);
}

class _StepAuditSession {
  final String convoId;
  final Map<String, int> toolCounts;
  final Map<String, Map<String, dynamic>> commandTracker;
  final List<Map<String, dynamic>> largeSteps;
  final Map<String, Map<String, dynamic>> sequenceTracker;
  final Map<String, List<String>> userPrompts;
  final String extractPrompts;
  final Map<String, int> stats;

  String? lastTool;
  int sequenceCount = 0;
  bool hasExtractedFirstPrompt = false;

  _StepAuditSession({
    required this.convoId,
    required this.toolCounts,
    required this.commandTracker,
    required this.largeSteps,
    required this.sequenceTracker,
    required this.userPrompts,
    required this.extractPrompts,
    required this.stats,
  });

  void processLine(String line) {
    if (line.trim().isEmpty) return;
    stats['totalSteps'] = (stats['totalSteps'] ?? 0) + 1;

    Map<String, dynamic> step;
    try {
      step = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    _processStepContent(step);
    final toolCalls = step['tool_calls'];
    if (toolCalls is List) {
      _processToolCalls(toolCalls);
    }
  }

  void _processStepContent(Map<String, dynamic> step) {
    final type = step['type'];
    final content = step['content']?.toString() ?? '';
    final cleanContent = stripSystemTags(content);
    final effectiveLength = (type == 'USER_INPUT')
        ? cleanContent.length
        : content.length;

    final shouldExtractPrompt =
        type == 'USER_INPUT' &&
        cleanContent.isNotEmpty &&
        (extractPrompts == 'all' ||
            (extractPrompts == 'first' && !hasExtractedFirstPrompt));
    if (shouldExtractPrompt) {
      userPrompts.putIfAbsent(convoId, () => []).add(cleanContent);
      hasExtractedFirstPrompt = true;
      stats['totalPromptsExtracted'] =
          (stats['totalPromptsExtracted'] ?? 0) + 1;
    }

    if (effectiveLength > 10000) {
      largeSteps.add({
        'convo': convoId,
        'step': step['step_index'] ?? 0,
        'type': type,
        'source': step['source'],
        'length': effectiveLength,
      });
    }
  }

  void _processToolCalls(List<dynamic> toolCalls) {
    for (final tc in toolCalls) {
      if (tc is! Map) continue;
      stats['totalToolCalls'] = (stats['totalToolCalls'] ?? 0) + 1;
      final toolName = _resolveToolName(tc);
      toolCounts[toolName] = (toolCounts[toolName] ?? 0) + 1;

      if (toolName == 'run_command') {
        _recordShellCommand(tc, convoId, commandTracker);
      }

      if (toolName == lastTool) {
        sequenceCount++;
      } else {
        _recordSequence(lastTool, sequenceCount, convoId, sequenceTracker);
        lastTool = toolName;
        sequenceCount = 1;
      }
    }
  }

  void finish() {
    _recordSequence(lastTool, sequenceCount, convoId, sequenceTracker);
  }
}

Future<void> auditSingleTranscript(
  String appDataDir,
  String convoId,
  Map<String, int> toolCounts,
  Map<String, Map<String, dynamic>> commandTracker,
  List<Map<String, dynamic>> largeSteps,
  Map<String, Map<String, dynamic>> sequenceTracker,
  Map<String, List<String>> userPrompts,
  String extractPrompts,
  Map<String, int> stats,
) async {
  final transcriptPath =
      '$appDataDir/brain/$convoId/.system_generated/logs/transcript.jsonl';
  final file = File(transcriptPath);
  if (!file.existsSync()) return;

  final session = _StepAuditSession(
    convoId: convoId,
    toolCounts: toolCounts,
    commandTracker: commandTracker,
    largeSteps: largeSteps,
    sequenceTracker: sequenceTracker,
    userPrompts: userPrompts,
    extractPrompts: extractPrompts,
    stats: stats,
  );

  final linesStream = file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in linesStream) {
    session.processLine(line);
  }
  session.finish();
}
