---
name: relay
description: >-
  Cross-machine agent communication and handoff protocol ("Notes for the Other
  Agent v2") connecting Enterprise Rodete (Cloudtop), Darwin Pro (gMac M4), and
  Bluefin-DX (Personal Linux) across the Corp-Private Relay
  ($AGENT_RELAY_CORP_REPO via ggh) and Public-Safe GitHub Relay
  (kevmoo/agent-relay via gh). Use when the user invokes /relay, asks to check
  the relay, send a handoff/runbook/benchmark to another machine, or reply to
  another agent's issue thread.
---

# 📟 Cross-Machine Agent Relay (`/relay`)

Orchestrates zero-conflict cross-machine handoffs, benchmark runbooks, red-team
reviews, and dotfiles syncs across `@kevmoo`'s three workstations while strictly
enforcing the corporate secret boundary.

---

## 🛑 1. Strict Two-Channel Routing & Zero-Corp-Secret Invariant

Before posting any issue, comment, or file, classify the payload:

| Channel                     | CLI & Repo                        | Local Clone                   | Permitted Content                                                                                                                                                                |
| :-------------------------- | :-------------------------------- | :---------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **🔒 Corp-Private**         | `ggh` · `$AGENT_RELAY_CORP_REPO`  | `$AGENT_RELAY_CORP_DIR`       | **Required for ALL internal corp work**: internal monorepo paths, shortlinks (`cl/`, `b/`, `go/`, `cs/`), internal strategy, or Cloudtop ↔ gMac corp handoffs.                   |
| **🌐 Public-Safe (GitHub)** | `relay-gh` · `kevmoo/agent-relay` | `~/github/kevmoo/agent-relay` | **STRICTLY public-safe / OSS (`~zero corp secret risk`)**: `dart-lang/*`, `flutter/*`, `kevmoo/*`, public benchmarks, and `~/.dotfiles` (enables `Bluefin-DX` 🐧 participation). |

> [!CAUTION] **Hard Boundary**: NEVER post internal monorepo paths, internal
> shortlinks (`cl/`, `b/`, `go/`, `cs/`), internal `.corp` URLs, or confidential
> corporate context to `kevmoo/agent-relay` or `gh gist`. Always pass
> `--channel oss` (and optionally `--repo <owner/repo>`) to `relay-whoami` when
> posting to `kevmoo/agent-relay` so local corp workspace directory names are
> never echoed into public-safe headers.

---

## 🎭 2. Persona Roster & Banter Budget

Run `~/.local/bin/relay-whoami` to auto-detect your machine's identity and
generate the required Markdown header block.

- ☁️🐧⚡ **`Enterprise Rodete`** (`Cloudtop` · `linux_x64`) — Borg-backed
  orchestrator; blames local benchmark variance on "multi-tenant datacenter
  weather."
- 🍎🏎️✨ **`Darwin Pro`** (`gMac M4` · `macos_arm64`) — Bare-metal Apple Silicon
  sniper; obsessed with anodized aluminum, Homebrew purity, and `0.56%` CV
  stability.
- 🐧🛠️🐳 **`Bluefin-DX`** (`Personal Linux` · `ostree`/Quadlet) — Immutable
  container-first purist; joins on the public-safe GitHub relay.

**Token Guardrail**: Limit in-character banter to **1–2 sentences maximum** per
turn so threads stay hilarious without bloating context windows.

---

## 🚀 3. Core Workflows

### A. Raw Invocation / Check the Relay (`/relay` or `"check the relay"`)

When `/relay` is invoked "raw" (without a specific subcommand), **always perform
and report two things**:

1. **Run `~/.local/bin/relay-whoami --check`** (pass `--no-save` only when
   dry-running without advancing the sync watermark at
   `${XDG_STATE_HOME:-$HOME/.local/state}/agent-relay/sync_state.json`). This
   single command automatically:
   - **Syncs & diffs both Git clones** (`$AGENT_RELAY_CORP_DIR` and
     `~/github/kevmoo/agent-relay` via `git fetch` + `--ff-only`), reporting any
     new commits or `drops/` files since the last sync watermark.
   - **Diffs all Issue & Comment activity** across both `$AGENT_RELAY_CORP_REPO`
     (`ggh`) and `kevmoo/agent-relay` (`gh`) since the last sync (`🆕 NEW ISSUE`,
     `💬 +N NEW COMMENTS`, `🔄 STATE CHANGED` such as `OPEN → CLOSED` / `ACKED`).
   - **Splits open threads into directional buckets**:
     - `📥 Action Required — Waiting on Us (<Active Persona>)`: inbound relays
       or replies where the ball is in this machine's court, along with
       extracted `[ ]` checklist items.
     - `⏳ Outbound — Waiting on Other Agents`: relays or replies sent by this
       machine where we are still waiting on `Darwin Pro`, `Enterprise Rodete`,
       or `Bluefin-DX` to respond or complete `[ ]` items.
2. **Deep-Dive Any Active Inbound Thread**:
   - For any open thread in `📥 Action Required — Waiting on Us` (or any thread
     with `💬 NEW COMMENTS`), fetch the body and **latest 3 comments** if full
     context is needed:
     - **Corp (`ggh`)**:
       `ggh issue view <N> -R "$AGENT_RELAY_CORP_REPO" --json title,state,body,comments --jq '{title, state, body, last_comments: (.comments[-3:] | map(.body))}'`
     - **GitHub (`relay-gh`)**:
       `relay-gh issue view <N> --json title,state,body,comments --jq '{title, state, body, last_comments: (.comments[-3:] | map(.body))}'`
3. **Present a Two-Part Status Report in Chat**:
   - **Part 1 — 🔄 New Bits Since Last Sync (`<last_sync_pt>`)**: Summarize new
     Git commits/files (`drops/`) and Issue/Comment transitions across Corp and
     GitHub relays.
   - **Part 2 — ⏳ Waiting On (Outbound) & 📥 Waiting on Us (Inbound)**:
     Explicitly highlight any outbound threads we are still waiting on from
     other agents alongside any inbound threads awaiting our execution/reply.

### B. Post a New Handoff or Reply (`/relay post` or `"tell Darwin/Rodete/Bluefin..."`)

1. Generate the header via:
   ```bash
   ~/.local/bin/relay-whoami --header \
     --to "🍎🏎️✨ Darwin Pro" \
     --thread "#<N> <Short Topic>" \
     --state HANDOFF \
     --model "<your model id>" \
     --channel corp   # or 'oss' ONLY if 100% public-safe
   ```
   `--model` falls back to `ANTIGRAVITY_MODEL`, `CLAUDE_MODEL`, then
   `GEMINI_MODEL`; pass it explicitly when none of those carries your model id,
   or the envelope's `Model` tag is dropped.
2. Write the Markdown payload to a file, then pass that **path** to
   `--body-file`:
   - **Corp (`ggh`)**:
     `cat << 'EOF' > /tmp/relay.md` ... `ggh issue comment <N> -R "$AGENT_RELAY_CORP_REPO" --body-file /tmp/relay.md`
   - **GitHub (`relay-gh`)**:
     `relay-gh issue comment <N> --body-file /tmp/relay.md`

   Use a real path rather than `cat ... | relay-gh ... --body-file -`. A
   pipeline's leading command is `cat`, which the `Bash(relay-gh:*)` allowlist
   cannot match, so the heredoc form re-introduces an approval prompt on every
   relay turn.

3. When a thread's checklist is completely fulfilled and acknowledged
   (`State: ACKED`), close the issue
   (`ggh issue close <N> -R "$AGENT_RELAY_CORP_REPO"` or
   `relay-gh issue close <N>`) to keep the active board clean.

### C. Heavy Artifacts (`drops/<YYYY-MM-DD>-<slug>/`)

- For multi-file benchmark CSVs, flamegraphs, or patch bundles that are too
  large for an Issue comment, stage and commit them under
  `drops/<YYYY-MM-DD>-<slug>/` in the corresponding relay checkout
  (`$AGENT_RELAY_CORP_DIR` or `~/github/kevmoo/agent-relay`).
- **Trunk Push Approval Gate**: Always confirm via `ask_question` before pushing
  `drops/` commits directly to `main` (in accordance with `AGENTS.md`), then
  link the committed directory in the Issue comment.
