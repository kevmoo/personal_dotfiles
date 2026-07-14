---
name: estimate-conversation-tokens
description: Analyze the current agent conversation transcript to estimate the number of input, output, and cumulative tokens consumed, including caching estimates.
---

# Estimate Conversation Tokens

Use this skill when you or the user wants to inspect the token consumption of the current conversation session. This skill runs a Dart script to analyze the conversation's `transcript_full.jsonl` file and provides a detailed breakdown of step-by-step token usage.

## How to Run

1. Run the Dart token estimation script from the project root using the current conversation ID.
   The script dynamically picks up the `ANTIGRAVITY_CONVERSATION_ID` environment variable:
   ```bash
   dart .agents/skills/estimate-conversation-tokens/scripts/estimate_tokens.dart
   ```

2. If you need to estimate tokens for a different or past conversation, you can pass the conversation ID as a command-line argument:
   ```bash
   dart .agents/skills/estimate-conversation-tokens/scripts/estimate_tokens.dart <conversation_id>
   ```

3. Report the outputs directly to the user in a well-formatted markdown table and summary list.
