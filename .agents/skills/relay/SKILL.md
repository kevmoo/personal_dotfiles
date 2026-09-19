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

| Channel                     | CLI & Repo                       | Local Clone                   | Permitted Content                                                                                                                                                                |
| :-------------------------- | :------------------------------- | :---------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **🔒 Corp-Private**         | `ggh` · `$AGENT_RELAY_CORP_REPO` | `$AGENT_RELAY_CORP_DIR`       | **Required for ALL internal corp work**: internal monorepo paths, shortlinks (`cl/`, `b/`, `go/`, `cs/`), internal strategy, or Cloudtop ↔ gMac corp handoffs.                   |
| **🌐 Public-Safe (GitHub)** | `gh` · `kevmoo/agent-relay`      | `~/github/kevmoo/agent-relay` | **STRICTLY public-safe / OSS (`~zero corp secret risk`)**: `dart-lang/*`, `flutter/*`, `kevmoo/*`, public benchmarks, and `~/.dotfiles` (enables `Bluefin-DX` 🐧 participation). |

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

### A. Check the Relay (`/relay` or `"check the relay"`)

1. Run `~/.local/bin/relay-whoami --check` to list open threads across both
   `$AGENT_RELAY_CORP_REPO` (`ggh`) and `kevmoo/agent-relay` (`gh`) in one call.
2. For any open issue addressed to this machine's persona (or awaiting reply),
   fetch the issue body and **only the latest 3 comments** to conserve tokens:
   - **Corp (`ggh`)**:
     `ggh issue view <N> -R "$AGENT_RELAY_CORP_REPO" --json title,state,body,comments --jq '{title, state, body, last_comments: (.comments[-3:] | map(.body))}'`
   - **GitHub (`gh`)**:
     `gh issue view <N> -R kevmoo/agent-relay --json title,state,body,comments --jq '{title, state, body, last_comments: (.comments[-3:] | map(.body))}'`
3. Present a concise summary of open action items (`[ ]`) and ask or execute as
   directed.

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
   Always pass `--model` explicitly: no environment variable carries it, so the
   envelope's `Model` tag is dropped unless you supply your own model id.
2. Stream the multi-line Markdown payload via `--body-file -` with a
   single-quoted heredoc
   (`cat << 'EOF' | ggh issue comment <N> -R "$AGENT_RELAY_CORP_REPO" --body-file -`).
3. When a thread's checklist is completely fulfilled and acknowledged
   (`State: ACKED`), close the issue
   (`ggh issue close <N> -R "$AGENT_RELAY_CORP_REPO"` or
   `gh issue close <N> -R kevmoo/agent-relay`) to keep the active board clean.

### C. Heavy Artifacts (`drops/<YYYY-MM-DD>-<slug>/`)

- For multi-file benchmark CSVs, flamegraphs, or patch bundles that are too
  large for an Issue comment, stage and commit them under
  `drops/<YYYY-MM-DD>-<slug>/` in the corresponding relay checkout
  (`$AGENT_RELAY_CORP_DIR` or `~/github/kevmoo/agent-relay`).
- **Trunk Push Approval Gate**: Always confirm via `ask_question` before pushing
  `drops/` commits directly to `main` (in accordance with `AGENTS.md`), then
  link the committed directory in the Issue comment.
