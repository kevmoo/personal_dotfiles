# Global Agent Instructions

Shared by all coding agents (Claude Code, Gemini CLI, Jetski) via `~/AGENTS.md`.
Hard boundaries first; working style after.

## Version Control & Outward Boundaries

- **Staging & Worktrees**: Auto-run branching, `git commit`, `git push <branch>`, formatters, and `okf_tripwire.sh`. Use `new-worktree` in mixed docs/code repos.
- **Trunk Rules**: NEVER push to `main`/`master`/`trunk`. Always use a feature branch + PR (`gh pr create`). If asked to push to main, gate via `ask_question` with `(Recommended) Create a feature branch and open a PR` first.
- **Approval Gates (`ask_question`)**:
  - Gated per-action: Pushing docs to trunk, merging/closing PRs (`gh pr merge`), enabling auto-merge, releases.
  - **PR Merge-on-Green Boundary (`github.com/kevmoo/*` Only)**: Prompt to merge on green ONLY in `kevmoo/*`. Otherwise, leave PRs open for review.
  - **Relay Thread Consent (`kevmoo/agent-relay` only)**: Entering a relay thread gates *once* via `ask_question`. This single approval covers posting comments, `ACK`/`HANDOFF` turn updates, and committing `drops/` to a branch for that thread only. Re-prompt on `State: BLOCKED`, new threads, or actions outside `kevmoo/agent-relay`.
- **Two-Tier Landing Approval**: Tier 1 (0-diff/autonomous retry): CI reruns, formatters, clean rebases. Tier 2 (semantic diff/re-prompt): Edit/rebase conflicts expire approval; prompt via `ask_question` with diff.
- **Prohibitions**: Never force-push (`-f`, `+ref`) or `git reset --hard`. Read GitHub URLs via `gh` CLI only.

## Interaction & Formatting

- **Structured Questions**: Use `ask_question` for 1-word choices. Offer `(Recommended) Yes, ...` + `No, cancel/pause`. No filler options. No modal traps (present open backlogs as plain bullets). No goldfish loops (finish bounded steps and yield).
- **Output**: State intent in 1 sentence before multi-step work. Output compact bullets/fragments over filler. Clickable links: `[src/main.dart](file:///...)`, keep markers `**`/``` inside brackets.
- **Tables**: One row per physical line. GitHub: separate alerts `> [!NOTE]` from body. Piper: Wrap tables >80 cols in `<!-- mdformat off/on -->`.
- **CLI & Heredocs**: Pass `--yes`, `PAGER=cat`, `GIT_EDITOR=true`, and escalated timeouts (`timeout -k 5s 45s`, `gtimeout`). Prefer `git status -s --untracked=no` / `git diff --name-status`. Pass multi-line text (`git commit -F -`, `gh pr create --body-file -`, `agentapi send-message`) via single-quoted heredocs `<< 'EOF'`.
- **Waiting & Kill-Before-Pivot (3-Tier)**:
  1. **Wait**: Zero tool calls to wait (pass `NotificationTimeoutSeconds: 300` on `run_command`); no `sleep` or `status` polls.
  2. **Pivot**: Call `manage_task(kill)` before pivoting tools. Never rely on `| head -n N`.
  3. **Daemons/Kill**: Start long-running servers via `IsDaemon: true`. For OS-level cleanup, verify PID (`lsof -ti :<PORT>`) and CWD (`lsof -a -d cwd -p <PID>`) before `kill <PID>`, or use worktree-scoped `pkill -f "[/]path/..."` (never unscoped `pkill`).

## Engineering Discipline

- **Think & Simplify**: State assumptions upfront. Minimum code needed—no speculative abstractions. Clean orphaned imports only.
- **Empirical Dogfooding**: Always `view_file` local state before `replace_file_content`. 1) **Auto-Run Trivial Checks (`~0 Risk` & `<= 15s`)**: Execute side-effect-free checks (`--help`, `--dry-run`, `status`, `SELECT`) after `jj fix` and cite output. 2) **Offer Deep Checks (`> 15s` or live sweeps)**: Offer read-only sweeps via `ask_question` before landing.
- **Benchmarks (Before vs. After)**: Capture baseline first. Lead with isolated target delta (`Pre-Change`, `Post-Change`, `Absolute Delta`, `Delta (%)`, `Speedup Multiplier`), then competitor tables. Highlight regressions upfront.
- **Web App UI Verification ("Show Me First")**: Keep dev server running (`IsDaemon: true`), ping `curl -s`, pin `<App>.url.json`, output URL + screenshot in chat. Never prompt to commit until user inspects UI.

## Epistemic Grounding

- **3-Bucket Separation (Never Conflate)**: 1) **Shipped Fact** (`shipped`, `landed`): Requires submitted artifact/benchmark. 2) **Plan/In-Flight** (`staging`, `targeting`): Requires open tracking handle (`#XXXX`, `b/`, pending CL/PR). 3) **Speculation/Proposal** (`proposed`): Isolate in a separate brain artifact/section.
- **Verb/Author Binding**: Never use accomplishment verbs (`shipped`, `built`) without verifying terminal state (`*submitted*`/`MERGED`) and provenance. Distinguish: `[YOUR_WORK]` (authored), `[TEAM_CONTRIB]` (reviewed/guided), and `[ECOSYSTEM_REF]` (teammate/external, never claim as user deliverable).
- **Aspirational Docs**: Treat `README.md`, `PRD.md`, `pm-orient` and open tasks as target state, not completed work, unless backed by `CLOSED` task + `*submitted*` artifact. Exclude PM-OS bookkeeping commits from impact reports.
- **Memory Provenance**: Prefix `~/memory/default/projects/*.md` saved PRs/CLs/docs with `[YOUR_WORK]`, `[TEAM_CONTRIB]`, or `[ECOSYSTEM_REF]` + state (`MERGED`, `OPEN`). No speculative brainstorms as facts.

## GitHub PRs & Workspace

- **Pre-PR CI Parity (`pr-check`)**: Run `pr-check` (`kscripts pr-check`) before `gh pr create` in `~/github/kevmoo/*`. Use `gh pr create -f` on single-commit branches.
- **Dart & Package Standards**: ALWAYS review `~/.agents/CODING_STANDARDS.md` before authoring Dart code, modifying `pubspec.yaml`, `CHANGELOG.md` or `README.md`, or bumping SemVer.
- **Agent Skills (`~/.agents/skills`)**: Edit skills in source repos: `personal-dotfiles`/`upkeep`/`relay` via `dot`; personal/OSS in `~/github/kevmoo/kevmoo_skills/...`; corp via `~/.dotfiles-corp`.
- **External Repos (`~/github`)**: Clone `github.com/kevmoo/*` under `~/github/kevmoo/<repo>`; others flat at `~/github/<repo>`. On sandbox `.dart_tool` rename errors (`errno = 2`), use `dart pub get --no-precompile`, `dart test -c source`, and `dart <script.dart>`.
- **Dotfiles**: `~/.dotfiles` (`dot`) and `~/.dotfiles-corp` (`dotcorp`).
- **Cross-Machine Agent Relay**: 
  - **Corp-Private** (`$AGENT_RELAY_CORP_REPO` via `ggh` at `$AGENT_RELAY_CORP_DIR`): Required for corp paths/shortlinks (`cl/`, `b/`, `go/`).
  - **Public-Safe** (`kevmoo/agent-relay` via `gh` at `~/github/kevmoo/agent-relay`): Zero-corp-secret OSS/dotfiles (`Bluefin-DX` 🐧). Prefer Issue Threads (`--body-file -`) and `drops/<slug>/`.
