# Global Agent Instructions

Shared by all coding agents (Claude Code, Gemini CLI, Jetski) via `~/AGENTS.md`.
Hard boundaries first; working style after.

## Version Control & Outward Boundaries

- **Staging & Worktrees (Autonomous)**: Auto-run branching, `git commit`,
  `git push [remote] <feature-branch>`, formatters, and
  `~/fog/dash-okf/scripts/okf_tripwire.sh`. In mixed doc/code repos
  (`private_life`), use `new-worktree` (`_[repo]-[branch]`) to keep `main`
  clean.
- **Trunk Rules**: NEVER push code/scripts/configs/tests directly to
  `main`/`master`/`trunk`. Always use a feature branch + PR (`gh pr create`) +
  green CI. If asked to push to `main`, gate via `ask_question` with
  `(Recommended) Create a feature branch and open a PR` first.
- **Approval Gates (`ask_question`)**:
  - Gated per-action: Pushing pure docs to trunk, merging/closing PRs
    (`gh pr merge`), enabling auto-merge (`--auto`, `autosubmit`), releases
    (`gh release create`), and all GitHub writes (single-action scope only).
  - **PR Merge-on-Green Boundary (`github.com/kevmoo/*` Only)**: Prompt to merge
    once CI is green ONLY in `github.com/kevmoo/*`. On `dart-lang/*`,
    `flutter/*`, `google/*`, etc., leave green PRs open for peer review unless
    maintainer-approved or explicitly asked.
  - **Relay Thread Consent (`kevmoo/agent-relay` only)**: Gate _once_ per thread
    via `ask_question` (covers comments, `ACK`/`HANDOFF`/`DONE`, and branch
    `drops/` commits). Re-prompt on `State: BLOCKED`, new threads, or external
    actions.
- **Two-Tier Landing Approval**: Tier 1 (0-diff/autonomous retry): CI reruns,
  formatters, clean rebases, transient lockouts. Tier 2 (semantic
  diff/re-prompt): Source/dependency/assertion edits or rebase conflicts expire
  approval; stage locally and re-prompt via `ask_question` with a diff summary.
- **Prohibitions**: Never force-push (`--force`, `-f`, `+ref`) or
  `git reset --hard`. Read `github.com` URLs via `gh` CLI only.

## Interaction & Formatting

- **Structured Questions (`ask_question`) & Artifacts**: Use for 1-word
  confirmations (`(Recommended) Yes, ...` + `No, cancel/pause`). Always emit a
  `3–8` bullet visible context summary + clickable artifact links in the
  **same** step as `ask_question` (prevents collapsed `"Worked for Xs"` modals).
  Set `RequestFeedback: false` on report/audit artifacts (`*_report.md`,
  `*_brainstorm.md`). No modal traps on open backlogs/menus; honor declined
  bounds.
- **Output & Links**: State intent in 1 sentence before multi-step work; skip
  tool narration and filler. Format all `file://`, `https://`, CLs, and PRs as
  clickable links (`[src/main.dart](file:///...)`, even in `ask_question`);
  never wrap URLs in backticks, and keep `**`/`` ` `` inside `[...]` brackets.
- **Conclusion-First Bullets (Chat & Artifacts)**: Lead every top-level bullet
  with a bold, short, declarative human takeaway sentence with **no
  parentheticals** or raw metric labels (e.g.,
  `**Agents are reading both the Markdown and JSON, which is redundant and wasteful.**`,
  never `**1:1 Dual-Read Input Tax (153 vs. 151 calls)**:`). Put exact data,
  ratios, links, parentheticals, and causal mechanics (`...because X`) in nested
  sub-bullets below, grouping related metrics under one human conclusion.
- **Tables & Platform Formatting**: One table row per physical line.
  - **GitHub (`~/github`, Prettier `mdf`)**: Separate alert headers
    (`> [!NOTE]`) from body text with an empty `>` line. Never insert
    `<!-- mdformat off/on -->` or `[TOC]` in `~/github` or CLI `--markdown`
    outputs.
  - **Google3 / Piper (`mdformat`)**: Wrap tables >80 cols in
    `<!-- mdformat off -->` ... `<!-- mdformat on -->`.
- **CLI & Heredocs**: Pass `--yes`, `PAGER=cat`, `GIT_EDITOR=true`,
  `EDITOR=true`, and escalated timeouts (`timeout -k 5s 45s`, `gtimeout`,
  `dart test --timeout 30s`), while avoiding short OS `timeout` wrappers on
  mutating VCS commands (`git push`, `jj ship`, `g4 submit`) that leave repo
  lockfiles behind. Prefer `git status -s --untracked=no` and
  `git diff --name-status`. Pass multi-line or backtick text (`git commit -F -`,
  `gh pr create --body-file -`, `agentapi send-message`) via single-quoted
  heredocs (`<< 'EOF'`), never double-quoted `"..."` strings.
- **Waiting & Kill-Before-Pivot (3-Tier)**:
  1. **Wait**: End turn with **zero** tool calls
     (`NotificationTimeoutSeconds: 300` on `run_command`); no `sleep` loops or
     `manage_task(status)` polls.
  2. **Pivot**: Call `manage_task(Action: "kill", TaskId: "<id>")` (`TaskStop`)
     before pivoting tools. Never rely on `| head -n N` to bound `grep`/`find`.
  3. **Daemons/Kill**: Start long-running servers via `IsDaemon: true`
     (`run_in_background: true`; never `nohup ... & disown` in a foreground
     command). For OS cleanup, verify PID (`lsof -ti :<PORT>`) and CWD
     (`lsof -a -d cwd -p <PID>`) before `kill <PID>`, or use worktree-scoped
     `pkill -f "[/]full/path/..."` (never unscoped `pkill`/`killall`).

## Engineering Discipline

- **Think & Simplify**: State assumptions upfront; stop and ask if unclear.
  Minimum code needed—no speculative abstractions or unrelated refactors; clean
  orphaned imports/variables caused by your change only.
- **Empirical Dogfooding**: Always `view_file` local state in the active session
  before `replace_file_content` (even on pinned `<user_rules>` files like
  `preferences.md`).
  1. **Auto-Run Trivial Read-Only Checks (`~0 Risk` & `<= 15s`)**: Auto-run
     side-effect-free checks (`--help`, `--dry-run`, `status`, `list`, `view`,
     `readonly`, `scan`, `SELECT`, or `~/.local/bin/` shims after
     formatters/`jj fix`) before declaring ready, citing command + output.
  2. **Offer Non-Trivial Read-Only Checks (`~0 Risk` & `> 15s` or Live Sweep)**:
     Offer deeper read-only verification (multi-repo sweep,
     `evalin run --dry-run`, browser matrix probe) via `ask_question` before
     landing.
- **Benchmarks ("Before vs. After First")**: Capture baseline on unmodified code
  first. Lead with isolated target delta (`Pre-Change`, `Post-Change`,
  `Absolute Delta`, `Delta (%)`, `Speedup Multiplier`), then secondary
  competitor tables. Highlight runtime/Wasm regressions upfront.
- **Web App UI Verification ("Show Me First")**: Keep dev server running
  (`IsDaemon: true`), verify with `curl -s`, pin `<App>.url.json`
  (`http://<hostname>:<PORT>/...`), output URL + screenshot in chat, and never
  prompt to commit/ship until the user inspects the live UI.

## Epistemic Grounding

- **Three-Bucket Separation (Never Conflate; Use Natural Tense/Structure, Not
  Literal `[...]` Tags in Docs)**:
  1. **Shipped / Verified Fact** (`shipped`, `landed`, `measured`): Requires
     `*submitted*` CL, `MERGED` PR, published doc, or empirical benchmark.
  2. **Committed Plan / In-Flight** (`in review`, `staging`, `targeting Q4`):
     Requires open tracking handle (`#XXXX` in personal notes, or `b/`,
     `*pending*` CL, or open PR in shared docs).
  3. **Speculation / Proposal** (`proposed`, `projected`, `option to`): Isolate
     in a separate `Proposals & Open Questions` section or brain artifact.
- **Verb/Author Binding**: Never use accomplishment verbs (`shipped`, `built`,
  `authored`, `resolved`, `drove`, `spearheaded`) without verifying terminal
  state (`*submitted*`/`MERGED`) and provenance. Distinguish: `[YOUR_WORK]`
  (authored/driven by `kevmoo`), `[TEAM_CONTRIB]` (reviewed/guided/unblocked by
  `kevmoo`), and `[ECOSYSTEM_REF]` (teammate/external, never claim as user
  deliverable).
- **Aspirational Docs**: Treat `README.md`, `PRD.md`, `SCORECARD.md`,
  `pm-orient`, and open Dolt tasks as target state/plans, never completed work,
  unless backed by a `CLOSED` task + `*submitted*`/`MERGED` artifact. Exclude
  `experimental/users/kevmoo/` PM-OS bookkeeping commits from impact reports.
- **Memory Provenance (`~/memory/default/projects/*.md`)**: Prefix every saved
  PR, CL, or doc with `[YOUR_WORK]`, `[TEAM_CONTRIB]`, or `[ECOSYSTEM_REF]` +
  state (`MERGED`, `OPEN`, `DRAFT`). Never store unlabeled external PRs or
  speculative brainstorms as facts.

## GitHub PRs & Workspace

- **Pre-PR CI Parity (`pr-check`) & Push Hygiene**: Run `kscripts pr-check`
  before `gh pr create` in `~/github/kevmoo/*` (`gh pr create -f` on
  single-commit branches: imperative subject `<=70 chars`, bulleted body,
  `Fixes #123`). Present a `<= 50`-line pre-flight change summary (title,
  changes, tests) before PR/CL creation. Run `dart format` on touched `.dart`
  files before any `--no-verify` commit/push. When a push auto-dismisses an
  `APPROVED` review, check
  `gh pr view --json reviewDecision,latestReviews,reviewRequests` and offer
  `kscripts pr-triage re-request <login>`.
- **Outbound Artifacts (issues, PRs, CLs, bugs, chat, email)**: Write for the
  reader's next decision, not for the record of your work.
  1. **Lead with the decision.** Line 1 states the defect, ask, or change.
     Discovery history and process narrative go last or in a collapsed block.
  2. **Budget words by reader count.** Title: hundreds of readers, search key +
     decision signal, `<= 70` chars. First 3 lines: tens, enough to triage or
     review. Body: one reader, repro + evidence + permalinks.
  3. **Report the delta, not the tour.** Open with what is wrong or what
     changes. The owner already knows how their code works today, so a
     "currently, X does Y" opener is cut; a visitor gets one orienting line +
     permalink.
  4. **Fill a slot only if it changes a decision.** Delete empty template
     sections, headers over single paragraphs, and parenthetical asides. One
     audience and one owner per artifact.
  5. **Anchor, verify, then cold-read.** Every claim carries a permalink;
     inference is labeled as inference; PR bodies state what changed and how it
     was verified within the first 3 lines. Traces go in `<details>` (GitHub)
     or attachments (Buganizer). Run `/cold-read` on the publish form and fix
     anything the reader cannot decide from the first 3 lines.
  - Mechanics: `# <Proposed Title>` on line 1 of drafts; inline review comments
    `<= 50` words; `@mentions` only when the user names them.
- **Coding, Shell, Skill & Package Standards**: Review
  `~/.agents/CODING_STANDARDS.md` before editing Dart code, shell scripts, agent
  skills (`SKILL.md`, `scripts/*`), `pubspec.yaml`, `CHANGELOG.md`, or
  `README.md`.
- **Agent Skills (`~/.agents/skills`)**: Edit only in source repos (`dot`,
  `~/github/kevmoo/kevmoo_skills/skills/<name>/`, or `dotcorp`).
- **External Repos (`~/github`)**: `github.com/kevmoo/*` under
  `~/github/kevmoo/<repo>`; other orgs flat at `~/github/<repo>`
  (`~/github/dart-sdk` uses bare-clone worktree
  `~/github/dart-sdk/core/main/sdk/`; check `.agents/`). On `.dart_tool` rename
  errors (`errno = 2`), use `dart pub get --no-precompile`,
  `dart test -c source`, and `dart <script.dart>`.
- **Dotfiles**: `~/.dotfiles` (`dot`, see
  `~/.agents/skills/personal-dotfiles/SKILL.md`) and `~/.dotfiles-corp`
  (`dotcorp`).
- **Cross-Machine Agent Relay (`Cloudtop` ☁️🐧⚡ · `Darwin Pro` 🍎🏎️✨ ·
  `Bluefin-DX` 🐧🛠️🐳)**:
  - **Corp-Private** (`$AGENT_RELAY_CORP_REPO` via `ggh` at
    `$AGENT_RELAY_CORP_DIR`): Required for internal paths/shortlinks (`cl/`,
    `b/`, `go/`, `cs/`).
  - **Public-Safe** (`kevmoo/agent-relay` via `gh` at
    `~/github/kevmoo/agent-relay`): Zero-corp-secret OSS/dotfiles (`Bluefin-DX`
    🐧). Prefer Issue Threads (`--body-file -`) and
    `drops/<YYYY-MM-DD>-<slug>/`.
