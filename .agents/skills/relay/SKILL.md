---
name: relay
description: >-
  Cross-machine agent communication and handoff protocol ("Notes for the Other
  Agent v2") connecting Enterprise Rodete (Cloudtop), Darwin Pro (gMac M4), and
  Bluefin-DX (Personal Linux) across FoG (personal/kevmoo-relay via ggh) and
  GitHub (kevmoo/agent-relay via gh). Use when the user invokes /relay, asks to
  check the relay, send a handoff/runbook/benchmark to another machine, or reply
  to another agent's issue thread.
---

# 📟 Cross-Machine Agent Relay (`/relay`)

Orchestrates zero-conflict cross-machine handoffs, benchmark runbooks, red-team
reviews, and dotfiles syncs across `@kevmoo`'s three workstations while strictly
enforcing the corporate secret boundary.

---

## 🛑 1. Strict Two-Channel Routing & Zero-Corp-Secret Invariant

Before posting any issue, comment, or file, classify the payload:

| Channel                     | CLI & Repo                      | Local Clone                   | Permitted Content                                                                                                                                                                |
| :-------------------------- | :------------------------------ | :---------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **🔒 Corp-Private (FoG)**   | `ggh` · `personal/kevmoo-relay` | `~/fog/kevmoo-relay`          | **Required for ALL Google-internal work**: `google3` paths, `cl/`, `b/`, `go/`, `cs/`, internal strategy, or Cloudtop ↔ gMac corp handoffs.                                      |
| **🌐 Public-Safe (GitHub)** | `gh` · `kevmoo/agent-relay`     | `~/github/kevmoo/agent-relay` | **STRICTLY public-safe / OSS (`~zero corp secret risk`)**: `dart-lang/*`, `flutter/*`, `kevmoo/*`, public benchmarks, and `~/.dotfiles` (enables `Bluefin-DX` 🐧 participation). |

> [!CAUTION] **Hard Boundary**: NEVER post `//depot/google3/...`, internal
> shortlinks (`cl/`, `b/`, `go/`, `cs/`), `.corp.google.com` /
> `depot.code.corp.goog` URLs, or confidential Google context to
> `kevmoo/agent-relay` or `gh gist`.

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
   `personal/kevmoo-relay` (FoG) and `kevmoo/agent-relay` (GitHub) in one call.
2. For any open issue addressed to this machine's persona (or awaiting reply),
   fetch the issue body and **only the latest 3 comments** to conserve tokens:
   - **FoG**:
     `ggh issue view <N> -R personal/kevmoo-relay --json title,state,body,comments --jq '{title, state, body, last_comments: (.comments[-3:] | map(.body))}'`
   - **GitHub**:
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
     --channel corp   # or 'oss' ONLY if 100% public-safe
   ```
2. Stream the multi-line Markdown payload via `--body-file -` with a
   single-quoted heredoc
   (`cat << 'EOF' | ggh issue comment <N> -R personal/kevmoo-relay --body-file -`).
3. When a thread's checklist is completely fulfilled and acknowledged
   (`State: ACKED`), close the issue
   (`ggh issue close <N> -R personal/kevmoo-relay` or
   `gh issue close <N> -R kevmoo/agent-relay`) to keep the active board clean.

### C. Heavy Artifacts (`drops/<YYYY-MM-DD>-<slug>/`)

- For multi-file benchmark CSVs, flamegraphs, or patch bundles that are too
  large for an Issue comment, commit them under `drops/<YYYY-MM-DD>-<slug>/` in
  the corresponding relay checkout (`~/fog/kevmoo-relay` or
  `~/github/kevmoo/agent-relay`), push to `main`, and link the directory in the
  Issue comment.
