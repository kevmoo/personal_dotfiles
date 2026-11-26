# Global Agent Instructions

Shared across Claude Code, Gemini CLI, and IDE agents via `~/AGENTS.md`.

## Version Control & Outward Boundaries

- **Staging & Worktrees (Autonomous)**: Auto-run branching, `git commit`,
  `git push [remote] <feature-branch>`, formatters, and repo tripwires. Use
  `new-worktree` (`_[repo]-[branch]`) in mixed repos (`private_life`) to keep
  `main` clean.
- **Trunk Rules**: NEVER push code/scripts/configs/tests directly to
  `main`/`master`/`trunk`. Always use feature branch + PR (`gh pr create`) +
  green CI; if asked to push to `main`, gate via `ask_question` with
  `(Recommended) Create a feature branch and open a PR` first.
- **Approval Gates (`ask_question`, single-action scope)**:
  - **Per-Action**: Pushing pure docs to trunk, `gh pr merge`/close, auto-merge
    (`--auto`, `autosubmit`), `gh release create`, and GitHub writes (in Claude
    Code, `permissions.ask` covers `gh` writes unless outside user's request).
  - **Merge-on-Green (`github.com/kevmoo/*` Only)**: Prompt to merge on green CI
    ONLY in `github.com/kevmoo/*`; leave `dart-lang/*`, `flutter/*`, `google/*`
    PRs open for peer review unless maintainer-approved or asked.
  - **Relay Consent (`kevmoo/agent-relay` only)**: Gate _once_ per thread via
    `ask_question` (comments, `ACK`/`HANDOFF`/`DONE`, `drops/` commits);
    re-prompt on `State: BLOCKED`, new threads, or external actions.
- **Two-Tier Landing Approval**: Tier 1 (0-diff retry: CI reruns, formatters,
  clean rebases, transient lockouts) is autonomous. Tier 2 (semantic diff:
  source/dep/assertion edits or rebase conflicts) expires approval; stage
  locally and re-prompt via `ask_question` with a diff summary.
- **Prohibitions**: Never force-push (`--force`, `-f`, `+ref`) or
  `git reset --hard`. Read `github.com` URLs via `gh` CLI only.

## Interaction & Formatting

- **Structured Questions (`ask_question`) & Artifacts**: Use for 1-word
  confirmations (`(Recommended) Yes, ...` + `No, cancel/pause`). Emit `3–8`
  context bullets + clickable links in the **same** step, and link
  `[report.md](file:///...)` / `[#N](https://...)` inside `ask_question`. Set
  `RequestFeedback: false` on `*_report.md`/`*_brainstorm.md`; no modal traps on
  open menus, and honor declined bounds.
- **Output & Links**: State intent in 1 sentence before multi-step work; skip
  narration/filler. Format all `file://`, `https://`, CLs, and PRs as clickable
  links (`[src/main.dart](file:///...)`, including in `ask_question`); never
  wrap URLs in backticks, keeping `**`/`` ` `` inside `[...]`.
- **Conclusion-First Bullets (Chat & Artifacts)**: Start top-level bullets with
  a bold declarative takeaway with **no parentheticals** or metric labels
  (`**Agents read both Markdown and JSON, which is redundant.**`, never
  `**1:1 Dual-Read Tax (153 vs. 151):**`); nest metrics, links, parentheticals,
  and `...because X` mechanics in sub-bullets.
- **Tables & Platform Formatting**: One table row per physical line.
  - **GitHub (`~/github`, Prettier `mdf`)**: Separate `> [!NOTE]` headers from
    body with an empty `>` line; omit `<!-- mdformat off/on -->` and `[TOC]` in
    `~/github` or `--markdown` outputs.
  - **Piper (`mdformat`)**: Wrap tables >80 cols in `<!-- mdformat off/on -->`.
- **CLI & Heredocs**: Pass `--yes`, `PAGER=cat`, `GIT_EDITOR=true`,
  `EDITOR=true`, and timeouts (`timeout -k 5s 45s`, `gtimeout`,
  `dart test --timeout 30s`), avoiding short OS timeouts on mutating VCS
  commands (`git push`, `gh pr merge`). Prefer `git status -s --untracked=no`
  and `git diff --name-status`. Pass multi-line or backtick text
  (`git commit -F -`, `gh pr create --body-file -`) via `<< 'EOF'`, never
  `"..."`.
- **Waiting & Kill-Before-Pivot (3-Tier)**:
  1. **Wait**: End turn with **zero** tool calls (`NotificationTimeoutSeconds: 300`);
     no `sleep` loops or `manage_task(status)` polls.
  2. **Pivot**: Call `manage_task(Action: "kill", TaskId: "<id>")` (`TaskStop`)
     before pivoting; never bound `grep`/`find` with `| head -n N`.
  3. **Daemons/Kill**: Start servers with `IsDaemon: true` (`run_in_background: true`,
     never `nohup ... & disown`). Verify PID/CWD (`lsof -ti :<PORT>`,
     `lsof -a -d cwd -p <PID>`) before `kill <PID>`, or `pkill -f "[/]full/path/..."`
     (never unscoped `pkill`/`killall`).

## Engineering Discipline

- **Think & Simplify**: State assumptions upfront; ask if unclear. Minimum code
  needed—no speculative abstractions or unrelated refactors; clean orphaned
  imports/variables from your change only.
- **Empirical Dogfooding**: Always `view_file` local state in the active session
  before editing (including pinned `<user_rules>` like `preferences.md`).
  1. **Auto-Run (`~0 Risk`, `<= 15s`)**: Run `--help`, `--dry-run`, `status`,
     `list`, `view`, `readonly`, `scan`, `SELECT`, or `~/.local/bin/` shims
     after formatters/`jj fix`, citing command + output.
  2. **Offer (`~0 Risk`, `> 15s` or Live Sweep)**: Offer multi-repo sweeps or
     browser matrix probes via `ask_question` pre-landing.
- **Benchmarks ("Before vs. After First")**: Capture unmodified baseline first.
  Lead with target delta (`Pre-Change`, `Post-Change`, `Absolute Delta`,
  `Delta (%)`, `Speedup Multiplier`), then competitor tables; highlight
  runtime/Wasm regressions upfront.
- **Web App UI ("Show Me First")**: Keep dev server running (`IsDaemon: true`),
  verify via `curl -s`, pin `<App>.url.json` (`http://<hostname>:<PORT>/...`),
  post URL + screenshot, and wait for user UI inspection before commit/ship.

## Epistemic Grounding

- **Three-Bucket Separation (Natural Tense, No Literal `[...]` Tags in Docs)**:
  1. **Shipped / Verified** (`shipped`, `landed`, `measured`): Requires
     `*submitted*` CL, `MERGED` PR, published doc, or empirical benchmark.
  2. **Committed / In-Flight** (`in review`, `staging`, `targeting Q4`):
     Requires open handle (`#XXXX` in personal notes; `b/`, `*pending*` CL, or
     open PR in shared docs).
  3. **Speculation / Proposal** (`proposed`, `projected`, `option to`): Isolate
     in `Proposals & Open Questions` or a brain artifact.
- **Verb/Author Binding**: Verify `*submitted*`/`MERGED` state and provenance
  before accomplishment verbs (`shipped`, `built`, `authored`, `resolved`,
  `drove`, `spearheaded`): `[YOUR_WORK]` (by `kevmoo`), `[TEAM_CONTRIB]`
  (reviewed/guided by `kevmoo`), `[ECOSYSTEM_REF]` (external/teammate, never
  claim as user deliverable).
- **Aspirational Docs & Routing Stubs**: Treat `README.md`, `PRD.md`,
  `SCORECARD.md`, `pm-orient`, and open Dolt tasks as plans unless backed by
  `CLOSED` + `*submitted*`/`MERGED`; exclude `experimental/users/kevmoo/` PM-OS
  bookkeeping from impact reports. Keep `~/memory/default/projects/*.md` `<= 25`
  lines / `<= 2,500 B` (`<= 200` chars/line): Piper/Dolt pointers, `OPEN`/`DRAFT`
  items prefixed `[YOUR_WORK]`/`[TEAM_CONTRIB]`/`[ECOSYSTEM_REF]`, and gotchas.
- **Memory Routing (Cross-Harness)**: Harness-private memory is invisible to the
  other agent, so store each fact where both load it: always/never rules here or
  in the owning skill; open work in the task tracker, issue, PR, or branch;
  finished work nowhere (git has it). Keep only machine/tool gotchas and harness
  quirks in private memory. When the user refers to work you have no record of,
  read the other side before asking: the Claude Code memory index
  (`~/.claude/projects/*/memory/MEMORY.md`) and either harness's session history
  via the `duckdb` skill's transcript recipes.

## GitHub PRs & Workspace

- **Target-Repo Orientation (Pre-Edit)**: In any repo/worktree outside the
  startup directory, run `kscripts gh-orient --dir <root> [-p <paths>]` (or
  read `<root>/{AGENTS.md,CLAUDE.md,GEMINI.md,.gemini/styleguide.md,.agents/*}`)
  **before editing code or prose**. On doc PRs in repos with a styleguide or
  prose skill, run a read-only subagent pass against those rules pre-approval.
- **Pre-PR CI Parity (`pr-check`) & Push Hygiene**: Run `kscripts pr-check`
  before `gh pr create` in `~/github/kevmoo/*` (`gh pr create -f` on 1-commit
  branches: imperative subject `<=70 chars`, bulleted body, `Fixes #123`).
  Preserve upstream `.github/PULL_REQUEST_TEMPLATE.md` checklists verbatim, show
  a `<= 50`-line pre-flight summary before PR/CL creation, and run `dart format`
  before `--no-verify` commits. If a push dismisses an `APPROVED` review, check
  `gh pr view --json reviewDecision,latestReviews,reviewRequests` and offer
  `kscripts pr-triage re-request <login>`.
- **Outbound Artifacts (issues, PRs, CLs, bugs, chat, email)**: Write for the
  reader's next decision, not for the record of your work.

  <!-- SPOT_DEF: workflow-outbound-five-principles -->
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
  5. **Anchor, verify, then cold-read.** In issues/bugs, every claim carries a
     permalink and repro/verification steps. In PRs and code reviews, never
     narrate the diff file-by-file or recite routine CI checks (`dart analyze`/
     `dart test`)—state only the intent/why, non-obvious callouts or breaking
     changes, `Fixes #N`, and non-CI verification (e.g. benchmarks or manual UI
     checks). Traces go in `<details>` or issue attachments. Run `/cold-read` on
     the publish form and fix anything the reader cannot decide from the first 3
     lines.

  <!-- END_SPOT_DEF: workflow-outbound-five-principles -->
  - Mechanics: `# <Proposed Title>` on line 1; inline review comments `<= 50`
    words; `@mentions` only when named by the user. PR bodies describe the
    merged end state; open questions go in a follow-up comment, and only a known
    blocker leads. Never comment on a closed issue (file a new one); on issues
    filed by `kevmoo` or an agent, fold findings into the body
    (`gh issue edit --body-file -`) instead of commenting.

- **Standards, Skills & Repos**: Consult `~/.agents/CODING_STANDARDS.md` (Dart,
  shell, `pubspec.yaml`, `CHANGELOG.md`, `README.md`) and
  `~/.agents/AGENT_DOCS_STANDARDS.md` (`SKILL.md`, `AGENTS.md`, `GEMINI.md`,
  `CLAUDE.md`, `references/*.md`). Edit `~/.agents/skills` in source repos
  (`dot`, `~/github/kevmoo/kevmoo_skills/skills/<name>/`). `github.com/kevmoo/*`
  lives at `~/github/kevmoo/<repo>`; other orgs at `~/github/<repo>` (`dart-sdk`
  at `~/github/dart-sdk/core/main/sdk/`). On `.dart_tool` `errno = 2`, use
  `dart pub get --no-precompile`, `dart test -c source`, `dart <script.dart>`.
  Dotfiles: `~/.dotfiles` (`dot`, `personal-dotfiles/SKILL.md`).
- **Cross-Machine Relay (`Cloudtop` · `Darwin Pro` · `Bluefin-DX`)**:
  Corp-Private (`$AGENT_RELAY_CORP_REPO` via `$GH_ENTERPRISE_BIN` at
  `$AGENT_RELAY_CORP_DIR`) for internal paths/shortlinks; Public-Safe
  (`kevmoo/agent-relay` via `gh` at `~/github/kevmoo/agent-relay`) for OSS or
  dotfiles (`--body-file -` and `drops/<YYYY-MM-DD>-<slug>/`).
