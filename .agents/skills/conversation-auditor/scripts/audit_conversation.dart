import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run audit_conversation.dart <app_data_dir> [convo_id1 convo_id2 ...] [--last N] [--prompts all|first|none]');
    exit(1);
  }

  var appDataDir = args[0];
  var targetConvos = <String>[];
  var extractPrompts = 'first'; // default to first prompt only to keep output manageable
  
  for (var i = 1; i < args.length; i++) {
    if (args[i] == '--last' && i + 1 < args.length) {
      var n = int.tryParse(args[i + 1]) ?? 1;
      targetConvos.addAll(getLastNConversations(appDataDir, n));
      i++;
    } else if (args[i] == '--prompts' && i + 1 < args.length) {
      extractPrompts = args[i + 1];
      i++;
    } else {
      targetConvos.add(args[i]);
    }
  }

  if (targetConvos.isEmpty) {
    targetConvos.addAll(getLastNConversations(appDataDir, 1));
  }

  targetConvos = targetConvos.toSet().toList();
  
  if (targetConvos.isEmpty) {
    print('No conversations found to audit.');
    return;
  }

  var toolCounts = <String, int>{};
  var commandTracker = <String, Map<String, dynamic>>{};
  var largeSteps = <Map<String, dynamic>>[];
  var sequenceTracker = <String, Map<String, dynamic>>{};
  var userPrompts = <String, List<String>>{};
  
  var stats = {
    'totalSteps': 0,
    'totalToolCalls': 0,
    'totalPromptsExtracted': 0,
  };

  for (var convoId in targetConvos) {
    await auditSingleTranscript(
      appDataDir, 
      convoId, 
      toolCounts, 
      commandTracker, 
      largeSteps, 
      sequenceTracker,
      userPrompts,
      extractPrompts,
      stats,
    );
  }

  print('--- Aggregated Audit Report for ${targetConvos.length} Conversation(s) ---');
  print('Conversations analyzed: ${targetConvos.join(', ')}');
  print('');
  print('📊 Audit Metadata Summary:');
  print('  - Total Steps (JSONL lines) parsed: ${stats['totalSteps']}');
  print('  - Total Tool Calls analyzed: ${stats['totalToolCalls']}');
  print('  - Total User Prompts extracted: ${stats['totalPromptsExtracted']}');
  print('  - Prompt Extraction Mode: $extractPrompts');
  
  print('\n1. Tool Usage Frequencies:');
  var sortedTools = toolCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (var entry in sortedTools) {
    print('  - ${entry.key}: ${entry.value}');
  }

  print('\n2. Repeated Tool Sequences (3+ consecutive calls, potential for bulk operations or new MCP):');
  var sortedSeqs = sequenceTracker.entries.toList()
    ..sort((a, b) => (b.value['instances'] as int).compareTo(a.value['instances'] as int));
  for (var entry in sortedSeqs) {
    var instances = entry.value['instances'];
    var convoCount = (entry.value['convos'] as Set<String>).length;
    print('  - ${entry.key}: $instances sequences across $convoCount convos');
  }

  print('\n3. Shell Commands Executed (Potential for scripting):');
  var sortedCmds = commandTracker.entries.toList()
    ..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));
  for (var entry in sortedCmds.take(15)) {
    var total = entry.value['total'];
    var convoCount = (entry.value['convos'] as Set<String>).length;
    var repoCount = (entry.value['repos'] as Set<String>).length;
    // Format command to one line if it has newlines
    var cmdDisplay = entry.key.replaceAll('\n', r'\n');
    if (cmdDisplay.length > 80) {
      cmdDisplay = '${cmdDisplay.substring(0, 77)}...';
    }
    print('  - [${total}x] $cmdDisplay (across $convoCount convo(s), $repoCount repo(s))');
  }

  print('\n4. Largest Context Hogs (Content > 10,000 chars):');
  largeSteps.sort((a, b) => (b['length'] as int).compareTo(a['length'] as int));
  for (var ls in largeSteps.take(5)) {
    print('  - Step ${ls['step']} in convo ${ls['convo']} (${ls['type']} from ${ls['source']}): ${ls['length']} characters');
  }

  if (extractPrompts != 'none' && userPrompts.isNotEmpty) {
    print('\n5. Distinct Tasks Performed (User Prompts):');
    for (var convoId in targetConvos) {
      if (userPrompts.containsKey(convoId)) {
        print('  - Convo $convoId:');
        for (var prompt in userPrompts[convoId]!) {
          var cleanPrompt = prompt.replaceAll('\n', r'\n');
          if (cleanPrompt.length > 200) {
            cleanPrompt = '${cleanPrompt.substring(0, 197)}...';
          }
          print('      * "$cleanPrompt"');
        }
      }
    }
  }
}

List<String> getLastNConversations(String appDataDir, int n) {
  var brainDir = Directory('$appDataDir/brain');
  if (!brainDir.existsSync()) return [];

  var convos = <Map<String, dynamic>>[];
  for (var entity in brainDir.listSync()) {
    if (entity is Directory) {
      var transcript = File('${entity.path}/.system_generated/logs/transcript.jsonl');
      if (transcript.existsSync()) {
        var id = entity.uri.pathSegments.lastWhere((e) => e.isNotEmpty);
        convos.add({
          'id': id,
          'modified': transcript.statSync().modified,
        });
      }
    }
  }
  
  convos.sort((a, b) => (b['modified'] as DateTime).compareTo(a['modified'] as DateTime));
  return convos.take(n).map((e) => e['id'] as String).toList();
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
  var transcriptPath = '$appDataDir/brain/$convoId/.system_generated/logs/transcript.jsonl';
  var file = File(transcriptPath);
  if (!file.existsSync()) return;

  String? lastTool;
  int sequenceCount = 0;
  bool hasExtractedFirstPrompt = false;

  var linesStream = file.openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (var line in linesStream) {
    if (line.trim().isEmpty) continue;
    stats['totalSteps'] = (stats['totalSteps'] ?? 0) + 1;
    
    Map<String, dynamic> step;
    try {
      step = jsonDecode(line) as Map<String, dynamic>;
    } catch (e) {
      continue;
    }

    var stepIndex = step['step_index'] ?? 0;
    var type = step['type'];
    var content = step['content']?.toString() ?? '';
    var contentLength = content.length;

    // Extract User Prompts
    if (type == 'USER_INPUT' && (extractPrompts == 'all' || (extractPrompts == 'first' && !hasExtractedFirstPrompt))) {
      var text = content.trim();
      if (text.isNotEmpty) {
        userPrompts.putIfAbsent(convoId, () => []).add(text);
        hasExtractedFirstPrompt = true;
        stats['totalPromptsExtracted'] = (stats['totalPromptsExtracted'] ?? 0) + 1;
      }
    }

    if (contentLength > 10000) {
      largeSteps.add({
        'convo': convoId,
        'step': stepIndex,
        'type': type,
        'source': step['source'],
        'length': contentLength,
      });
    }

    var toolCalls = step['tool_calls'];
    if (toolCalls is List && toolCalls.isNotEmpty) {
      for (var tc in toolCalls) {
        if (tc is! Map) continue;
        stats['totalToolCalls'] = (stats['totalToolCalls'] ?? 0) + 1;
        
        dynamic toolNameRaw = tc['name'];
        if (toolNameRaw == null && tc['function'] is Map) {
          toolNameRaw = tc['function']['name'];
        }
        
        String toolName;
        if (toolNameRaw is Map && toolNameRaw.containsKey('name')) {
          toolName = toolNameRaw['name'].toString();
        } else {
          toolName = toolNameRaw?.toString() ?? tc.toString();
        }

        toolCounts[toolName] = (toolCounts[toolName] ?? 0) + 1;

        if (toolName == 'run_command') {
          dynamic argsData = tc['args'] ?? tc['arguments'];
          if (argsData == null && tc['function'] is Map) {
            argsData = tc['function']['arguments'];
          }

          if (argsData is String) {
            try { argsData = jsonDecode(argsData); } catch (_) { argsData = <String, dynamic>{}; }
          }

          if (argsData is Map) {
            dynamic cmd = argsData['CommandLine'] ?? argsData['command_line'] ?? argsData['command'];
            String repo = argsData['Cwd']?.toString() ?? 'unknown';
            
            if (cmd != null) {
              if (cmd is String && cmd.startsWith('"') && cmd.endsWith('"')) {
                try { cmd = jsonDecode(cmd); } catch (_) {}
              }
              var cmdStr = cmd.toString();
              commandTracker.putIfAbsent(cmdStr, () => {'total': 0, 'convos': <String>{}, 'repos': <String>{}});
              commandTracker[cmdStr]!['total']++;
              (commandTracker[cmdStr]!['convos'] as Set<String>).add(convoId);
              (commandTracker[cmdStr]!['repos'] as Set<String>).add(repo);
            }
          }
        }

        if (toolName == lastTool) {
          sequenceCount++;
        } else {
          if (sequenceCount > 2 && lastTool != null) {
            sequenceTracker.putIfAbsent(lastTool, () => {'instances': 0, 'convos': <String>{}});
            sequenceTracker[lastTool]!['instances']++;
            (sequenceTracker[lastTool]!['convos'] as Set<String>).add(convoId);
          }
          lastTool = toolName;
          sequenceCount = 1;
        }
      }
    }
  }

  if (sequenceCount > 2 && lastTool != null) {
    sequenceTracker.putIfAbsent(lastTool, () => {'instances': 0, 'convos': <String>{}});
    sequenceTracker[lastTool]!['instances']++;
    (sequenceTracker[lastTool]!['convos'] as Set<String>).add(convoId);
  }
}
