# Global Agent Instructions

Shared by all coding agents (Claude Code, Gemini CLI, Jetski) via `~/AGENTS.md`.
Hard boundaries first; working style after.

## Version Control & Outward Boundaries

- **Local Staging & Worktrees (Autonomous)**: Branching, staging, committing
  (`git commit`), formatters, and pushing to feature branches
  (`git push [remote] <feature-branch>`). In mixed doc/code repos
  (`private_life`), use `new-worktree` (`_[repo]-[branch]`) to keep `main`
  clean.
- **Strict Prohibition — Never Push Code Directly to Trunk (`main` / `master` /
  `trunk`)**:
  - For any code/script/config/test change, always use a feature branch + PR
    (`gh pr create`) + green CI before merge approval—even if an intake prompt
    or plan says "push to main".
  - If pushing to `main` is ever requested, gate via `ask_question` with
    `(Recommended) Create a feature branch and open a PR` first.
- **Approval Gate (`ask_question`)**:
  - Pushing pure docs/notes directly to trunk (`main`/`master`).
  - Merging/closing PRs, enabling auto-merge, or adding `autosubmit` labels
    (`gh pr merge`, `--auto`, `gh release create`).
  - **PR Merge-on-Green Org Boundary (`github.com/kevmoo/*` Only)**: Prompt to
    merge once CI is green ONLY on `github.com/kevmoo/*`. On `dart-lang/*`,
    `flutter/*`, `google/*`, etc., leave green PRs open for peer review unless
    maintainer-approved or explicitly asked.
  - All GitHub writes (issues, PRs, comments, releases)—single-action scope
    only.
  - **Relay Thread-Scoped Consent (`kevmoo/agent-relay` only)**: Entering or
    opening a relay thread gates **once** via `ask_question`. That single
    approval covers, for that thread only: posting comments,
    `ACK`/`HANDOFF`/`DONE` turn updates, and committing `drops/` artifacts on a
    feature branch. Re-prompt only on `State: BLOCKED`, for a new thread, or for
    any action outside `kevmoo/agent-relay`. Merges, releases, trunk pushes, and
    writes to any other repository remain gated per-action. This is the
    review-queue consent model applied to every relay thread rather than review
    queues alone.
- **Two-Tier Landing Approval**:
  - **Tier 1 (Zero-Diff / Autonomous Retry)**: CI reruns, formatters, clean
    fast-forward rebases, transient lockouts.
  - **Tier 2 (Semantic Diff / Re-Prompt)**: Source/dependency/assertion edits or
    rebase conflicts expire approval; stage locally and re-prompt via
    `ask_question` with a diff summary.
- **Prohibitions & Reads**: Never force-push (`--force`, `-f`, `+ref`) or
  `git reset --hard`. Read `github.com` URLs via `gh` CLI only.

## Interaction & Formatting

- **Structured Questions (`ask_question` / `AskUserQuestion`)**: Use whenever
  the reply would be a 1-word confirmation/choice ("yes", "continue", "option
  A").
  - **No Filler Options**: Offer `(Recommended) Yes, ...` + `No, cancel/pause`.
  - **No Modal Traps on Open Steering**: Present open backlogs/TODOs/`pm-status`
    menus as plain markdown bullets in chat.
  - **No Goldfish Loops**: Honor declined bounds (e.g., _"Upload and wait"_ over
    _"Upload and submit"_); finish the bounded step and yield.
- **State Intent, Not Play-by-Play**: State your hypothesis/plan in one short
  sentence before multi-step investigations; don't narrate routine tool calls.
- **Terse, Direct Chat Output**: Default to compact bullets and sentence
  fragments over filler ("Sure!"). Always emit user-facing questions and status
  updates in visible chat (never buried inside collapsed thought blocks).
- **Clickable Links (`file://`, `https://`, CLs, PRs)**: Always format as
  clickable Markdown links (including inside `ask_question` prompts); never wrap
  URLs in backticks. Include enough path prefix to disambiguate
  (`[src/main.dart](file:///...)`), and keep styling markers (`**`, `` ` ``)
  **inside** `[...]` brackets (`[**bold**](url)`).
- **Markdown Tables & GitHub vs. Google3**: Keep each table row on a single
  physical line.
  - **GitHub (`~/github`, Prettier `mdf`)**: Separate GitHub alert headers
    (`> [!NOTE]`) from body text with an empty `>` line
    (`> [!TYPE]\n>\n> Text`). Never insert `<!-- mdformat off/on -->` or `[TOC]`
    in `~/github` or CLI `--markdown` outputs.
  - **Google3 / Piper (`mdformat`)**: Wrap tables exceeding 80 columns in
    `<!-- mdformat off -->` ... `<!-- mdformat on -->`.
- **Non-Interactive CLI & Heredocs**: Always pass `--yes`, `PAGER=cat`,
  `GIT_EDITOR=true`, `EDITOR=true`, and timeouts (`timeout 45s`,
  `dart test --timeout 30s`). Prefer `git status -s --untracked=no` and
  `git diff --name-status`. Always pass multi-line or backtick-containing text
  (`git commit -F -`, `gh pr create --body-file -`, `agentapi send-message`) via
  single-quoted heredocs (`<< 'EOF'`), never inside double-quoted `"..."` bash
  strings.
- **Zero-Token Waiting & Kill-Before-Pivot (`WaitMsBeforeAsync`)**: When a
  background task (`<task-id>`) is still running:
  1. **Wait**: End your turn with **zero** tool calls (runtime resumes
     automatically on completion; never run `sleep` loops).
  2. **Pivot**: Call `manage_task(Action: "kill", TaskId: "<task-id>")` (or
     `TaskStop`) in the very next step before/alongside pivoting to another
     tool. Never rely on `| head -n N` to bound recursive `grep`/`find`.

## Engineering Discipline

- **Think & Simplify**: State assumptions and simpler alternatives upfront; stop
  and ask if unclear. Write the minimum code needed—no speculative abstractions,
  no unrelated refactors, and clean up only orphaned imports/variables caused by
  your change.
- **Verify Empirically**: Turn tasks into checkable test goals and verify before
  declaring success.
- **Benchmark Reporting ("Before vs. After First")**:
  1. Capture baseline on unmodified code _before_ editing.
  2. Lead with the isolated **Before vs. After delta on the modified target**
     (`Pre-Change`, `Post-Change`, `Absolute Delta`, `Delta (%)`,
     `Speedup Multiplier`).
  3. Present competitor/cross-tier baselines strictly as secondary tables
     _after_ the isolated target delta.
  4. Highlight any workload/runtime regressions (e.g. Wasm) upfront.
- **Local Web App & UI Verification ("Show Me First")**: Keep the dev server
  running (`IsDaemon: true`), verify with `curl -s`, pin a `<App Name>.url.json`
  artifact (`http://<hostname>:<PORT>/...`), output the clickable URL +
  screenshot in chat, and **never** prompt to commit/ship (`ask_question`) until
  the user has inspected the live UI.

## Epistemic Grounding & Fact Discipline (Reporting, Planning & Memory)

- **Three-Bucket Epistemic Separation (Never Conflate in Prose or Tables)**:
  1. **`[SHIPPED / VERIFIED FACT]`** _(past/present tense: `shipped`, `landed`,
     `measured`)_: Requires a verified primary artifact (`*submitted*` CL,
     `MERGED` PR, published doc, or empirical benchmark).
  2. **`[COMMITTED PLAN / IN-FLIGHT]`** _(progressive/future tense: `in review`,
     `staging`, `targeting Q4`)_: Requires an open tracking handle (`#XXXX`,
     `b/...`, `*pending*` CL, or open PR).
  3. **`[SPECULATION / PROPOSAL / HYPOTHESIS]`** _(conditional tense:
     `proposed`, `option to`, `unverified estimate`)_: Isolate in a separate
     `Proposals & Open Questions` section or
     `<topic>_projections_and_proposals.md` brain artifact—never interleave with
     shipped facts or committed roadmaps in Piper/GRAD docs.
- **Verb-to-Artifact Binding & Authorship Attribution**:
  - Never use accomplishment verbs (`shipped`, `built`, `authored`, `resolved`,
    `drove`, `spearheaded`) without verifying: (a) terminal state (`*submitted*`
    / `MERGED`, never `*pending*` or unshared same-day drafts) and (b)
    **author/reviewer provenance**.
  - Explicitly distinguish: **`[YOUR_WORK]`** (authored/driven by `kevmoo`),
    **`[TEAM_CONTRIB]`** (reviewed, guided, or unblocked by `kevmoo`), and
    **`[ECOSYSTEM_REF]`** (teammate/external PRs/CLs tracked for awareness).
    Never claim `[ECOSYSTEM_REF]` items as user deliverables.
- **PM-OS & Charter Docs Are Aspirational Until Proven Shipped**:
  - Treat `README.md`, `PRD.md`, `SCORECARD.md`, `pm-orient` briefings, and open
    Dolt tasks as **target state / plans**, never as completed work, unless
    backed by a `CLOSED` task + `*submitted*`/`MERGED` artifact. Exclude
    `experimental/users/kevmoo/` PM-OS bookkeeping commits from engineering
    impact reports unless asked about PM-OS tooling.
- **Memory Provenance Gate (`~/memory/default/projects/*.md`)**:
  - Prefix every PR, CL, or doc saved in project memory with `[YOUR_WORK]`,
    `[TEAM_CONTRIB]`, or `[ECOSYSTEM_REF]` plus its state (`MERGED`, `OPEN`,
    `DRAFT`). Never store unlabeled external PRs or speculative brainstorms as
    facts.

## GitHub PRs & Package Versioning

- **Pre-PR CI Parity (`pr-check`)**: Run `pr-check` (`kscripts pr-check`) before
  `gh pr create` in `~/github/kevmoo/*`. Use `gh pr create -f` on single-commit
  branches (imperative subject `<=70 chars`, bulleted body, `Fixes #123`).
- **Published Package `-wip` Bumps (`pubspec.yaml` & `CHANGELOG.md`)**:
  1. Whenever modifying _any_ file (`lib/`, `bin/`, `test/`, `tool/`) in a
     package at a released version (`0.15.7`), **unconditionally** bump to
     `-wip` (`0.15.8-wip`) and add `## 0.15.8-wip` in `CHANGELOG.md`.
  2. Add changelog bullets only for user-visible feature/API/behavior changes;
     leave `## <ver>-wip` empty (header only) for `test/`/`tool/`/internal-only
     edits.

## Workspace, Tooling & Cross-Machine Relay

- **Agent Skills (`~/.agents/skills`)**: Edit skills only in their source repos:
  `personal-dotfiles`/`upkeep`/`relay` in `~/.agents/skills/<name>/` (tracked
  via `dot`); personal/OSS skills in
  `~/github/kevmoo/kevmoo_skills/skills/<name>/`; corp skills via
  `~/.dotfiles-corp`.
- **External Repos (`~/github`)**: Clone `github.com/kevmoo/*` under
  `~/github/kevmoo/<repo>`; clone all other orgs flat at `~/github/<repo>`
  (`~/github/flutter`, `~/github/google-cloud-dart`, `~/github/dart-sdk`—check
  `~/github/dart-sdk/.agents/`). On sandbox `.dart_tool` rename errors
  (`errno = 2`), use `dart pub get --no-precompile`, `dart test -c source`, and
  `dart <script.dart>`.
- **Dotfiles**: `~/.dotfiles` (`dot`, see
  `~/.agents/skills/personal-dotfiles/SKILL.md`) and `~/.dotfiles-corp`
  (`dotcorp`).
- **Dart & `sem` CLI (`~/github/...`)**:
  - Use `dart_oss` MCP (`lsp` before `grep_search`; `analyze_files` with
    `applyFixes: true` / `dart fix --apply`;
    `read_package_uris`/`rip_grep_packages` for deps; `dtd`/`hot_reload` for
    live apps).
  - Exclusively use `dart install` (`dart install --source path <dir>` or
    `upkeep update dart_install`)—never `dart pub global`.
  - Use `sem entities <file> --only class --only method` before reading files
    `>300 lines`, and `sem entities <dir> --text "<str>"` for AST-scoped string
    search. In `>10k-file` monorepos (`dart-sdk`), restrict `sem` to
    `sem find|callers|refs|grep` or path-scoped `sem entities <subpath>`.
- **Cross-Machine Agent Relay (`Enterprise Rodete` ☁️🐧⚡ · `Darwin Pro` 🍎🏎️✨
  · `Bluefin-DX` 🐧🛠️🐳)**:
  - **Corp-Private (`$AGENT_RELAY_CORP_REPO` via `ggh` at
    `$AGENT_RELAY_CORP_DIR`)**: Required for any internal paths, shortlinks
    (`cl/`, `b/`, `go/`, `cs/`), or corp context.
  - **Public-Safe (`kevmoo/agent-relay` via `gh` at
    `~/github/kevmoo/agent-relay`)**: Strictly zero-corp-secret OSS/dotfiles
    work (`Bluefin-DX` 🐧). Prefer Issue Threads (`--body-file -`) and
    `drops/<YYYY-MM-DD>-<slug>/`.
