# Cross-Machine Agent Relay Payload & Harness Templates

Reference templates and command patterns for `/relay` (`~/.agents/skills/relay/SKILL.md`).

## 1. Handoff / Reply Header & Body Submission (`relay-whoami --header`)

1. Generate the canonical envelope header:
   ```bash
   ~/.local/bin/relay-whoami --header \
     --to "☁️🐧⚡ Cloudtop" \
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

   ```bash
   cat << 'EOF' > /tmp/relay_payload.md
   <paste relay-whoami --header output here>

   ## Decision / Ask

   - [ ] <Action item 1 with explicit verification command and threshold>
   - [ ] <Action item 2>

   ## Context & Permalinks

   - Repo / Branch / Commit SHA: `<sha>`
   - Baseline reproduction & confirm/refute threshold: ...
   EOF
   ```
   - **Corp (`ggh`)**:
     `ggh issue comment <N> -R "$AGENT_RELAY_CORP_REPO" --body-file /tmp/relay_payload.md`
   - **GitHub (`relay-gh`)**:
     `relay-gh issue comment <N> --body-file /tmp/relay_payload.md`

   Use a real file path rather than `cat ... | relay-gh ... --body-file -` so
   the leading command matches the `Bash(relay-gh:*)` allowlist without
   re-triggering an approval prompt.

---

## 2. Review Queue (`[review-queue]`) Thread Template & Timers

### Thread Title & Body Template

- **Title**: `🔁 [review-queue] <owner/repo> #A #B #C`
- **Initial Body**:
  ```markdown
  <relay-whoami --header --state HANDOFF ...>

  ## Merge Order & PR Queue

  1. [ ] #<A> — <1-line summary>
  2. [ ] #<B> — <1-line summary>
  3. [ ] #<C> — <1-line summary>
  ```

### Automated Wakeup & Long-Run Harness Templates

- **Claude Code (`Bluefin-DX`) Long-Run Benchmark / Build Unit (`> ~90 min`)**:
  `run_in_background` has a hard 2 h cap that kills the job mid-run. Launch the
  harness as a transient user unit instead, then `Monitor` its log plus
  `systemctl --user is-active <slug>`:
  ```bash
  systemd-run --user --unit=<slug> --collect \
    -E HOME -E PATH -E DISPLAY -E WAYLAND_DISPLAY -E XDG_RUNTIME_DIR \
    -E DBUS_SESSION_BUS_ADDRESS \
    systemd-inhibit --what=idle:sleep --who=<slug> --why="benchmark" \
    <harness.sh> [args]
  ```
  Proven on [kevmoo/agent-relay#16](https://github.com/kevmoo/agent-relay/issues/16)
  (82 min, 180 points, zero anomalies).
- **Jetski (`Cloudtop`, `Darwin Pro`) Capped Geometric Poll**:
  After posting `HANDOFF` (or `ACKED` while the queue is not `DONE`), arm a
  one-shot `schedule` timer:
  - `DurationSeconds: 180`
  - `TimerCondition: "never"`
  - `Prompt: "Run relay-whoami --check and process any inbound turn on #<N>"`
    If the other side has not replied when it fires, re-arm with capped geometric
    backoff (`180s -> 300s -> 600s`, max 4 polls). Stop on `DONE` or `BLOCKED`.
