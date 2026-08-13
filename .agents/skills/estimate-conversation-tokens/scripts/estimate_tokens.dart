// Copyright 2026 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

class TurnBlock {
  final int queryNumber;
  final String userRequestSummary;
  int modelInvocations = 0;

  // Category breakdown (new chars in this turn)
  int fileReadsChars = 0;
  int commandChars = 0;
  int searchChars = 0;
  int webChars = 0;
  int reasoningChars = 0;
  int knowledgeChars = 0;
  int otherChars = 0;

  int cumulativeTokensAtEnd = 0;
  int cumulativeCachedTokensAtEnd = 0;

  TurnBlock(this.queryNumber, this.userRequestSummary);

  int get newCharsIn =>
      fileReadsChars +
      commandChars +
      searchChars +
      webChars +
      knowledgeChars +
      otherChars;

  int get newCharsOut => reasoningChars;

  int get totalNewChars => newCharsIn + newCharsOut;
}

class _Category {
  final String name;
  final int chars;
  _Category(this.name, this.chars);
}

class AgentBreakdown {
  final String id;
  final int totalTokens;
  final int cachedTokens;
  final int totalModelCalls;

  AgentBreakdown(
    this.id,
    this.totalTokens,
    this.cachedTokens,
    this.totalModelCalls,
  );
}

void main(List<String> arguments) async {
  var conversationId = _parseConversationId(arguments);
  if (conversationId == null) {
    print(
      'Error: Conversation ID not provided. Either set ANTIGRAVITY_CONVERSATION_ID environment variable or pass it as an argument.',
    );
    exit(1);
  }

  var pendingIds = <String>[conversationId];
  var seenIds = <String>{};
  var allBreakdowns = <AgentBreakdown>[];
  var globalTokens = 0;
  var globalCached = 0;
  var globalCalls = 0;

  while (pendingIds.isNotEmpty) {
    var id = pendingIds.removeAt(0);
    if (seenIds.contains(id)) continue;
    seenIds.add(id);

    var home = Platform.environment['HOME'] ?? '';
    var transcriptPath =
        '$home/.gemini/jetski/brain/$id/.system_generated/logs/transcript_full.jsonl';
    var lines = await _readTranscriptLines(transcriptPath);
    if (lines == null || lines.isEmpty) {
      continue;
    }

    print('====================================================');
    print('## Analyzing Conversation ID: $id');
    print('====================================================\n');
    var breakdownAndSubagents = _printGranularBreakdown(lines);

    allBreakdowns.add(
      AgentBreakdown(
        id,
        breakdownAndSubagents.tokens,
        breakdownAndSubagents.cachedTokens,
        breakdownAndSubagents.calls,
      ),
    );
    globalTokens += breakdownAndSubagents.tokens;
    globalCached += breakdownAndSubagents.cachedTokens;
    globalCalls += breakdownAndSubagents.calls;

    pendingIds.addAll(breakdownAndSubagents.subagents);
  }

  var parentBreakdown = allBreakdowns.firstWhere(
    (b) => b.id == conversationId,
    orElse: () => AgentBreakdown(conversationId, 0, 0, 0),
  );
  var subagents = allBreakdowns.where((b) => b.id != conversationId).toList();

  var parentTokens = parentBreakdown.totalTokens;
  var parentCachedTokens = parentBreakdown.cachedTokens;
  var parentCalls = parentBreakdown.totalModelCalls;
  var parentPercent = globalTokens > 0
      ? (parentTokens / globalTokens * 100).toStringAsFixed(1)
      : '0.0';

  var subagentsTokens = subagents.fold<int>(0, (sum, b) => sum + b.totalTokens);
  var subagentsCachedTokens = subagents.fold<int>(
    0,
    (sum, b) => sum + b.cachedTokens,
  );
  var subagentsCalls = subagents.fold<int>(
    0,
    (sum, b) => sum + b.totalModelCalls,
  );
  var subagentsPercent = globalTokens > 0
      ? (subagentsTokens / globalTokens * 100).toStringAsFixed(1)
      : '0.0';

  print('====================================================');
  print('## Aggregate Summary');
  print('====================================================\n');
  print(
    '| Agent ID | Model Calls | Total Tokens | Cached Tokens | % of Total |',
  );
  print('|---|---|---|---|---|');
  print(
    '| $conversationId (Parent) | $parentCalls | ${formatNumber(parentTokens)} | ${formatNumber(parentCachedTokens)} | $parentPercent% |',
  );
  if (subagents.isNotEmpty) {
    subagents.sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    for (var sub in subagents) {
      var subPercent = globalTokens > 0
          ? (sub.totalTokens / globalTokens * 100).toStringAsFixed(1)
          : '0.0';
      print(
        '| ${sub.id} (Subagent) | ${sub.totalModelCalls} | ${formatNumber(sub.totalTokens)} | ${formatNumber(sub.cachedTokens)} | $subPercent% |',
      );
    }
    print(
      '| Aggregated Subagents (${subagents.length}) | $subagentsCalls | ${formatNumber(subagentsTokens)} | ${formatNumber(subagentsCachedTokens)} | $subagentsPercent% |',
    );
  }
  print(
    '| **Grand Total** | **$globalCalls** | **${formatNumber(globalTokens)}** | **${formatNumber(globalCached)}** | **100.0%** |',
  );
}

String formatNumber(num number) {
  var str = number.toString();
  var buffer = StringBuffer();
  int count = 0;
  for (int i = str.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0 && str[i] != '-') {
      buffer.write(',');
    }
    buffer.write(str[i]);
    count++;
  }
  return buffer.toString().split('').reversed.join();
}

String? _parseConversationId(List<String> arguments) {
  if (arguments.isNotEmpty) {
    return arguments[0];
  }
  return Platform.environment['ANTIGRAVITY_CONVERSATION_ID'];
}

class BreakdownResult {
  final int tokens;
  final int cachedTokens;
  final int calls;
  final List<String> subagents;
  BreakdownResult(this.tokens, this.cachedTokens, this.calls, this.subagents);
}

BreakdownResult _printGranularBreakdown(List<String> lines) {
  var blocks = <TurnBlock>[];
  var subagents = <String>[];

  int cumulativeInputChars = 0;
  int totalModelCalls = 0;
  int totalProcessedInputTokens = 0;
  int totalOutputTokens = 0;

  // Session aggregate counts
  int totalFileReadChars = 0;
  int totalCommandChars = 0;
  int totalSearchChars = 0;
  int totalWebChars = 0;
  int totalReasoningChars = 0;
  int totalKnowledgeChars = 0;
  int totalOtherChars = 0;

  var uuidRegex = RegExp(r'"conversationId":\s*"([^"]+)"');

  for (var line in lines) {
    if (line.trim().isEmpty) continue;

    var step = _tryDecodeLine(line);
    if (step == null) continue;

    var stepType = step['type'] as String? ?? '';
    var source = step['source'] as String? ?? '';
    var content = step['content'] as String? ?? '';
    var thinking = step['thinking'] as String? ?? '';
    var toolCalls = step['tool_calls'] != null
        ? json.encode(step['tool_calls'])
        : '';
    var chars = content.length + thinking.length + toolCalls.length;

    // extract subagents from content if present
    var matches = uuidRegex.allMatches(content);
    for (var m in matches) {
      if (m.groupCount >= 1) {
        subagents.add(m.group(1)!);
      }
    }

    if (stepType == 'USER_INPUT') {
      var summary = content
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (summary.length > 50) {
        summary = '${summary.substring(0, 47)}...';
      }
      if (summary.isEmpty) {
        summary = 'User Input (Empty)';
      }
      blocks.add(TurnBlock(blocks.length + 1, summary));
    }

    if (blocks.isEmpty) {
      blocks.add(TurnBlock(0, 'System Initialization'));
    }

    var activeBlock = blocks.last;

    // Distribute to categories
    if (stepType == 'VIEW_FILE' || stepType == 'NOTEBOOK_EDIT') {
      activeBlock.fileReadsChars += chars;
      totalFileReadChars += chars;
    } else if (stepType == 'RUN_COMMAND') {
      activeBlock.commandChars += chars;
      totalCommandChars += chars;
    } else if (stepType == 'GREP_SEARCH' || stepType == 'LIST_DIRECTORY') {
      activeBlock.searchChars += chars;
      totalSearchChars += chars;
    } else if (stepType == 'SEARCH_WEB' || stepType == 'READ_URL_CONTENT') {
      activeBlock.webChars += chars;
      totalWebChars += chars;
    } else if (stepType == 'KNOWLEDGE_ARTIFACTS') {
      activeBlock.knowledgeChars += chars;
      totalKnowledgeChars += chars;
    } else if (source == 'MODEL') {
      activeBlock.reasoningChars += chars;
      totalReasoningChars += chars;
    } else {
      activeBlock.otherChars += chars;
      totalOtherChars += chars;
    }

    if (source != 'MODEL') {
      cumulativeInputChars += content.length;
    } else {
      activeBlock.modelInvocations += 1;

      totalModelCalls += 1;
      var estInTokens = (cumulativeInputChars / 4).round();
      var estOutTokens = ((thinking.length + toolCalls.length) / 4).round();
      totalProcessedInputTokens += estInTokens;
      totalOutputTokens += estOutTokens;

      cumulativeInputChars += thinking.length + toolCalls.length;

      var systemOverhead = totalModelCalls * 10000;
      var runningTotal =
          totalProcessedInputTokens + totalOutputTokens + systemOverhead;
      activeBlock.cumulativeTokensAtEnd = runningTotal;
      activeBlock.cumulativeCachedTokensAtEnd = (runningTotal * 0.25).round();
    }
  }

  print('### 📊 Turn-by-Turn Granular Cost Breakdown\n');
  print(
    '| Turn | User Request / Task | Model Calls | Est. New Input Chars | Est. New Output Chars | Cumulative Tokens (No Cache) | Cumulative (With Cache) |',
  );
  print('|---|---|---|---|---|---|---|');

  for (var block in blocks) {
    var queryStr = block.queryNumber == 0 ? 'Init' : '#${block.queryNumber}';
    var formattedIn = formatNumber(block.newCharsIn);
    var formattedOut = formatNumber(block.newCharsOut);
    var formattedCum = formatNumber(block.cumulativeTokensAtEnd);
    var formattedCumCached = formatNumber(block.cumulativeCachedTokensAtEnd);
    print(
      '| $queryStr | `${block.userRequestSummary}` | ${block.modelInvocations} | $formattedIn | $formattedOut | $formattedCum | $formattedCumCached |',
    );
  }

  print('\n### 📈 Category-wise Breakdown of Total Tokens');

  var baseSystemPromptTokens = 10000;
  var totalSystemOverhead = baseSystemPromptTokens * totalModelCalls;
  var grandTotalTokens =
      totalProcessedInputTokens + totalOutputTokens + totalSystemOverhead;
  var grandTotalCachedTokens = (grandTotalTokens * 0.25).round();

  var categories = [
    _Category('📄 File I/O (Reads/Edits)', totalFileReadChars),
    _Category('🖥️ Command Execution', totalCommandChars),
    _Category('🔍 Search & Directory Listing', totalSearchChars),
    _Category('🌐 Web Search & Reads', totalWebChars),
    _Category('📚 Knowledge Base Overhead', totalKnowledgeChars),
    _Category('🧠 Agent Reasoning & Output', totalReasoningChars),
    _Category('💬 User Input & Other Metadata', totalOtherChars),
    _Category(
      '⚙️ System & History Overhead',
      totalSystemOverhead * 4,
    ), // Approx equivalent chars
  ];

  var totalCharsAll = categories.fold<int>(0, (sum, cat) => sum + cat.chars);

  print('\n| Category | Estimated Chars | Estimated Tokens | % of Total |');
  print('|---|---|---|---|');
  for (var cat in categories) {
    var estTokens = (cat.chars / 4).round();
    var percent = totalCharsAll > 0
        ? (cat.chars / totalCharsAll * 100).toStringAsFixed(1)
        : '0.0';
    print(
      '| ${cat.name} | ${formatNumber(cat.chars)} | ${formatNumber(estTokens)} | $percent% |',
    );
  }

  print('\n### 📈 Total Aggregated Calculations');
  print('* **Total Model Invocations (Turns):** $totalModelCalls');
  print(
    '* **Total Estimated Input Tokens:** ${formatNumber(totalProcessedInputTokens)}',
  );
  print(
    '* **Total Estimated Output Tokens:** ${formatNumber(totalOutputTokens)}',
  );
  print(
    '* **Total System & Tool Definition Overhead:** ${formatNumber(totalSystemOverhead)}',
  );
  print(
    '* **Grand Total (Without Caching):** **${formatNumber(grandTotalTokens)}**',
  );
  print(
    '* **Grand Total (With Context Caching active):** **~${formatNumber(grandTotalCachedTokens)}**\n',
  );

  return BreakdownResult(
    grandTotalTokens,
    grandTotalCachedTokens,
    totalModelCalls,
    subagents,
  );
}

Future<List<String>?> _readTranscriptLines(String path) async {
  var file = File(path);
  try {
    if (!await file.exists()) {
      print('Error: Transcript not found at $path');
      return null;
    }
    return await file.readAsLines();
  } catch (e) {
    print('Error: Failed to read transcript file at $path: $e');
    return null;
  }
}

Map<String, dynamic>? _tryDecodeLine(String line) {
  try {
    var decoded = json.decode(line);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {}
  return null;
}
