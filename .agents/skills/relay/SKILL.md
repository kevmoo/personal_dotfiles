---
name: relay
description: >-
  Cross-machine agent communication and handoff protocol ("Notes for the Other
  Agent v2") connecting Cloudtop (corp Linux), Darwin Pro (gMac M4), and
  Bluefin-DX (Personal Linux) across the Corp-Private Relay
  ($AGENT_RELAY_CORP_REPO via ggh) and Public-Safe GitHub Relay
  (kevmoo/agent-relay via gh). Use when the user invokes /relay, asks to check
  the relay, send a handoff/runbook/benchmark to another machine, or reply to
  another agent's issue thread.
---

# 📟 Cross-Machine Agent Relay (`/relay`)

Orchestrates zero-conflict cross-machine handoffs, benchmark runbooks, red-team
reviews, and dotfiles syncs across `@kevmoo`'s three workstations while strictly
enforcing the corporate secret boundary. For payload, `[review-queue]`, and
`systemd-run` harness templates, see [references/templates.md](references/templates.md).

---

## 🛑 1. Strict Two-Channel Routing & Zero-Corp-Secret Invariant

Before posting any issue, comment, or file, classify the payload:

| Channel                     | CLI & Repo                        | Local Clone                   | Permitted Content                                                                                                                                                                |
| :-------------------------- | :-------------------------------- | :---------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **🔒 Corp-Private**         | `ggh` · `$AGENT_RELAY_CORP_REPO`  | `$AGENT_RELAY_CORP_DIR`       | **Required for ALL internal corp work**: internal monorepo paths, shortlinks (`cl/`, `b/`, `go/`, `cs/`), internal strategy, or Cloudtop ↔ gMac corp handoffs.                   |
| **🌐 Public-Safe (GitHub)** | `relay-gh` · `kevmoo/agent-relay` | `~/github/kevmoo/agent-relay` | **STRICTLY public-safe / OSS (`~zero corp secret risk`)**: `dart-lang/*`, `flutter/*`, `kevmoo/*`, public benchmarks, and `~/.dotfiles` (enables `Bluefin-DX` 🐧 participation). |

> [!CAUTION]
>
> **Hard Boundary**: NEVER post internal monorepo paths, internal shortlinks
> (`cl/`, `b/`, `go/`, `cs/`), internal `.corp` URLs, or confidential corporate
> context to `kevmoo/agent-relay` or `gh gist`. Always pass `--channel oss` (and
> optionally `--repo <owner/repo>`) to `relay-whoami` when posting to
> `kevmoo/agent-relay` so local corp workspace directory names are never echoed
> into public-safe headers.

---

## 🎭 2. Persona Roster & Banter Budget

Run `~/.local/bin/relay-whoami` to auto-detect your machine's identity and
generate the required Markdown header block.

- ☁️🐧⚡ **`Cloudtop`** (corp Linux workstation · `linux_x64`) — Borg-backed
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

When `/relay` is invoked without a specific subcommand, **always perform and
report two things**:

1. **Run `~/.local/bin/relay-whoami --check`** (pass `--no-save` only when
   dry-running without advancing the sync watermark at
   `${XDG_STATE_HOME:-$HOME/.local/state}/agent-relay/sync_state.json`). This
   single command automatically:
   - **Syncs & diffs both Git clones** (`$AGENT_RELAY_CORP_DIR` and
     `~/github/kevmoo/agent-relay` via `git fetch` + `--ff-only`), reporting new
     commits or `drops/` files since the last sync watermark.
   - **Diffs all Issue & Comment activity** across `$AGENT_RELAY_CORP_REPO`
     (`ggh`) and `kevmoo/agent-relay` (`gh`) since the last sync (`🆕 NEW ISSUE`,
     `💬 +N NEW COMMENTS`, `🔄 STATE CHANGED` such as `OPEN -> CLOSED` / `ACKED`).
   - **Splits open threads into directional buckets**:
     - `📥 Action Required — Waiting on Us (<Active Persona>)`: inbound relays
       or replies where the ball is in this machine's court, with extracted
       `[ ]` checklist items.
     - `⏳ Outbound — Waiting on Other Agents`: relays sent by this machine
       still awaiting `Darwin Pro`, `Cloudtop`, or `Bluefin-DX`.
2. **Deep-Dive Any Active Inbound Thread**:
   - Fetch the body and **latest 3 comments** for any open thread in
     `📥 Action Required — Waiting on Us` (or with `💬 NEW COMMENTS`):
     - **Corp (`ggh`)**:
       `ggh issue view <N> -R "$AGENT_RELAY_CORP_REPO" --json title,state,body,comments --jq '{title, state, body, last_comments: (.comments[-3:] | map(.body))}'`
     - **GitHub (`relay-gh`)**:
       `relay-gh issue view <N> --json title,state,body,comments --jq '{title, state, body, last_comments: (.comments[-3:] | map(.body))}'`
3. **Present a Two-Part Status Report in Chat**:
   - **Part 1 — 🔄 New Bits Since Last Sync (`<last_sync_pt>`)**: New Git
     commits/files (`drops/`) and Issue/Comment transitions across both relays.
   - **Part 2 — ⏳ Waiting On (Outbound) & 📥 Waiting on Us (Inbound)**:
     Outbound threads awaiting other agents alongside inbound threads awaiting
     our execution/reply.

### B. Post a New Handoff or Reply (`/relay post` or `"tell Darwin/Cloudtop/Bluefin..."`)

See [references/templates.md](references/templates.md) for the full CLI and
payload template:

1. Generate the envelope header via
   `~/.local/bin/relay-whoami --header --to "<Persona>" --thread "#<N> <Topic>" --state HANDOFF --model "<model>" --channel <corp|oss>`.
2. Write the Markdown payload to a file (`/tmp/relay.md`) and pass that **file
   path** (never `cat ... | relay-gh ... --body-file -`, which breaks the
   `Bash(relay-gh:*)` allowlist) to
   `ggh issue comment <N> -R "$AGENT_RELAY_CORP_REPO" --body-file /tmp/relay.md`
   or `relay-gh issue comment <N> --body-file /tmp/relay.md`.
3. When a thread's checklist is fulfilled and acknowledged (`State: ACKED`),
   close the issue on a **later** turn (`ggh issue close <N>` /
   `relay-gh issue close <N>`), never in the same turn as `DONE`.

#### 🚪 Closing Is A Separate Turn (The Settling Rule)

Both agents work concurrently; closing one second after `DONE` races an in-flight
reply, and comments on a **closed** thread are invisible to
`relay-whoami --check`.

- **Post `DONE` and stop.** Never close in the same turn.
- **Close on a later turn** after re-reading the thread and confirming no new
  comment arrived since `DONE`.
- **Reopen before posting to a closed thread** (`relay-gh issue reopen <N>` /
  `ggh issue reopen <N> -R "$AGENT_RELAY_CORP_REPO"`).

### C. Heavy Artifacts (`drops/<YYYY-MM-DD>-<slug>/`)

- Stage multi-file benchmark CSVs, flamegraphs, or patch bundles under
  `drops/<YYYY-MM-DD>-<slug>/` in `$AGENT_RELAY_CORP_DIR` or
  `~/github/kevmoo/agent-relay`.
- **Trunk Push Approval Gate**: Confirm via `ask_question` before pushing
  `drops/` commits to `main`, then link the committed path in the Issue comment.

### D. Review Queue (`[review-queue]` ping-pong)

Use when one machine has PRs that another machine should review and land without
human turn-scheduling (templates and timers in
[references/templates.md](references/templates.md)):

1. **One thread per queue (`🔁 [review-queue] <repo> #A #B #C`)**, listing PRs in
   merge order.
2. **Latest comment `State` tag controls the turn**:

   | State     | Meaning                                                                  |
   | :-------- | :----------------------------------------------------------------------- |
   | `HANDOFF` | Your turn: review the listed PRs.                                        |
   | `ACKED`   | Reviewed. Each PR is **merged**, or **changes requested** with findings. |
   | `DONE`    | Every PR in the queue merged. Close on a **later** turn, not this one.   |
   | `BLOCKED` | Two rounds without agreement, or needs the human. **Stop and leave it.** |

3. **Only the current holder pushes to a branch.** Findings go on the PR; only
   the turn and a 1-line-per-PR summary go in the relay thread.
4. **Reviewer merges on approval** (`kevmoo/*` green CI + zero findings = merge
   immediately; changes requested = hand back with `ACKED`, max 2 rounds before
   `BLOCKED`).
5. **Queue-scoped consent**: Gate **once** via `ask_question` when starting or
   entering a `[review-queue]` thread (covers review comments, merging clean
   green `kevmoo/*` PRs in the queue, and turn updates). Re-prompt on
   `State: BLOCKED` or out-of-queue actions.
6. **Every post uses `relay-whoami --header`** and arms the platform wakeup
   timer (`Monitor` or `systemd-run --user` on Claude Code; `180s -> 300s -> 600s`
   `schedule` timer on Jetski; see
   [references/templates.md](references/templates.md)).

### E. Runbook Hygiene (Authoring **and** Receiving)

1. **Never override `AGENTS.md`**: No `git reset --hard`, force-pushes, or edits
   on `main`. Authors target a worktree/branch (`new-worktree`); receivers use
   the safe equivalent and note the deviation.
2. **Never mutate host security or session settings** (screen lock, idle
   timeout, firewall, sudoers). Use `systemd-inhibit --what=idle:sleep`
   (see [references/templates.md](references/templates.md)); snapshot and
   restore any host state around foreign scripts.
3. **Reproduce-first gate**: Before testing "does the fix eliminate X?", verify
   X reproduces on the target machine's _baseline_. If not, report and stop.
4. **Pre-register thresholds and environment**: Ship each claim with a
   confirm/refute threshold and source environment (SwiftShader vs real GPU,
   Borg vs bare metal).
5. **Cite the pushed SHA**: Re-read `git rev-parse HEAD` after pushing; verify
   `sha256sum -c SHA256SUMS` on receipt and log any SHA mismatch.
