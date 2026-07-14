---
name: conversation-auditor
description: Introspects conversation history to suggest new tools, skills, MCP servers, or identify context window hogs and optimization opportunities.
---

# Conversation Auditor

## Overview
This skill audits previous conversation transcripts to help the user identify ways to tune their agentic coding experience. It looks for commonly performed actions, repetitive low-level commands, tool sequences that can be aggregated, and places where the context window is being heavily utilized.

## When to use
Trigger this skill when the user asks to "audit my conversation", "suggest new skills", "find MCP server opportunities", or "introspect conversation history".

## Workflow

1. **Determine the Audit Target:** If the user doesn't specify an exact scope (e.g., they just type `/conversation-auditor`), you MUST use the `ask_question` tool to present a multiple-choice question asking them what they want to audit. Provide options like:
   - "(Recommended) My most recent conversation"
   - "My last 5 conversations (Aggregated)"
   - "My last 10 conversations (Aggregated)"
   - "A specific conversation ID (Write-in)"
2. **Run the Audit Script:** 
   Execute the provided Dart script:
   ```bash
   # Assuming the agent is running in a standard setup, you can locate the script relative to this skill file.
   # For a specific conversation:
   dart run <path_to_this_skill_directory>/scripts/audit_conversation.dart <path_to_app_data_dir> <conversation_id>
   
   # For the last N conversations (aggregated):
   dart run <path_to_this_skill_directory>/scripts/audit_conversation.dart <path_to_app_data_dir> --last 3
   ```
3. **Analyze the Output:** 
   Read the output of the script. The script will highlight:
   - Tool Usage Frequencies
   - Repeated Tool Sequences
   - Raw Shell Commands Executed
   - Largest Context Hogs
4. **Generate Recommendations:**
   Use your own intelligence (as an LLM) to interpret the script's output and present a structured markdown report to the user in an Artifact (e.g. `audit_report.md`).
   
   **Use this analytical framework to categorize your findings:**
   - **The "Iterative Struggle" (High Frequency, 1 Conversation):** Was a command or tool run many times in just one conversation? The agent likely got stuck brute-forcing a problem or parsing data. *Recommendation:* An MCP server for structured data access or a better error-handling wrapper.
   - **The "Project Boilerplate" (Consistent Frequency, Multiple Convos, 1 Repo):** Was a command run across several conversations, but always in the same workspace? *Recommendation:* Extract into a **Project-Specific Skill** (`.agents/skills/`) or add a Knowledge Item (KI) so the agent knows the exact build/test commands.
   - **The "Global Gap" (Consistent Frequency, Multiple Convos, Multiple Repos):** Is the agent relying on raw shell tools (like `ps aux`, `lsof`, `git log`, `find`) across many different workspaces? *Recommendation:* Suggest a **Global Skill** (`~/.gemini/config/skills/`) or a dedicated **MCP Server** (like a Git MCP or System Monitor MCP).

5. **Deliver Findings:** Provide the report to the user, highlighting the highest-value optimization opportunities based on the framework above.
