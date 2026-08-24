# Global Agent Instructions

Shared by all coding agents (Claude Code, Gemini CLI) via symlinks to
~/AGENTS.md. Hard boundaries first; working style after. Git/GitHub safety
is also enforced by each agent's permission settings — these rules state intent.

## Version Control & Outward Boundaries

- **Local Staging & Worktrees (Autonomous)**: Branching, staging, committing (`git commit`), formatters, and pushing to feature/PR branches (`git push [remote] <feature-branch>`).
  - **Worktree Isolation for Code**: When developing code in mixed documentation/code repositories (e.g. `private_life`), use `new-worktree` to create a dedicated sibling worktree (`_[repo]-[branch]`). This keeps the primary repository checkout clean on `main` for ongoing note-taking and live task operations.
- **Mandatory Pull Requests for Code**: When modifying source code (`.dart`, `.go`, `.py`, scripts, build configurations, test suites), NEVER push directly to default/trunk (`main`, `master`, `trunk`). Always stage on a feature branch, create a Pull Request (`gh pr create`), and verify CI check runs pass before requesting merge approval.
- **Approval Gate (`ask_question`)**:
  - Pushing pure documentation/notes directly to default/trunk (`main`, `master`, `trunk`).
  - Merging/closing PRs, publishing releases (`gh pr merge`, `gh release create`).
  - GitHub writes (issues, PRs, comments, releases). Single-action scope only.
- **Two-Tier Landing Approval**:
  - **Tier 1 (Zero-Diff / Autonomous Retry)**: Submit/merge approval covers mechanical fixes: CI test runs, auto-formatters, clean fast-forward rebases, transient lockouts. Re-run landing without re-prompting.
  - **Tier 2 (Semantic Diff / Re-Prompt Required)**: Approval expires immediately if source code (`.dart`, `.go`, `.py`), dependencies, or test assertions change, or non-trivial rebase conflicts occur. Stage locally, then prompt via `ask_question` with diff summary.
- **Prohibitions**: Never force-push (`--force`, `-f`, `+ref`) or hard-reset (`git reset --hard`).
- **Reads**: Read-only inspection is always safe. Read github.com URLs via `gh` CLI only.

## Interaction

- **Approvals, Confirmations, and Choices**: use the structured question tool
  (`AskUserQuestion` / `ask_question`) whenever asking a question where my answer
  would otherwise be typing a quick 1-word reply ("yes", "continue", "proceed",
  "option A"). One click beats a typed reply every time.
- **Guardrails against Overuse**:
  - **No Filler Options**: when confirming a straightforward next step (`Yes, continue`),
    don't fabricate silly options (`sit and do nothing`). Provide a clean `(Recommended) Yes, ...`
    alongside a simple `No, cancel/pause`.
  - **No Modal Traps on Open Steering**: when presenting an open backlog, TODO items
    (`pm_status`), or soliciting general direction ("What should we work on next?"),
    present them as **plain markdown bullets in chat**. A multiple-choice box on open
    menus forces a rigid UI state right when I might want to meander, combine ideas,
    or give open-ended steering.
  - **No Goldfish Loops (Honor Declined Options)**: when I select an option that
    bounds or stops execution (e.g. picking *"Upload and wait"* over *"Upload and
    submit"*), **respect the negative boundary**. Do not immediately fire another
    `ask_question` soliciting the very branch I just passed on. Finish the bounded
    task and yield the floor cleanly.
- **State intent, not play-by-play**: before starting a multi-step
  investigation or changing direction, state your hypothesis or plan in one
  short sentence so I can redirect you early. Don't narrate routine tool
  calls (grep, file reads) that the UI already shows.
- **Clickable Links (Files & URLs)**: Format files (`file://`), web URLs (`https://`), CLs, and PRs as clickable Markdown links. Never wrap HTTP/HTTPS URLs in code backticks (which disables autolinking).
  - To avoid ambiguity or confusion (e.g., distinguishing between different `BUILD` files or common names), include enough preceding path components in the link text (e.g., [src/main.dart](file:///absolute/path/to/src/main.dart) instead of `[main.dart]`).
  - **Formatting Containment Rules**:
    - Place markdown brackets `[` and parentheses `(` on the absolute outside of the link (e.g. `[text](url)`).
    - Any formatting style (such as bold `**` or code backticks `` ` ``) must be enclosed **inside** the brackets `[]` (e.g., `[**bold link**](url)` or `[` `ClassName` `](url)`). Never wrap the link text brackets or the entire link in styling markers.
- **Markdown Tables**: When displaying structured data in markdown tables, keep each row on a single continuous line. Do not insert physical line breaks (`\n`) inside cells. Let the Markdown renderer handle column wrapping automatically to preserve standard table structure.
  - **mdformat Protection**: In Google3/Piper workspaces, the automated formatter (`mdformat` / `jj fix`) aggressively wraps table rows exceeding 80 columns into broken multi-line colon (`:`) syntax. To prevent this, always wrap tables exceeding 80 columns in `<!-- mdformat off -->` and `<!-- mdformat on -->` block guards.
- **Terse, Bulleted Output**: Default to compact bullet points over conversational prose. Fragment sentences are encouraged. Skip conversational filler ("Sure!", "I'd be glad to help..."). Optimize for token efficiency, high information density, and fast scannability.
- **Direct Chat Output (No Thought Collapse)**: always output user-facing
  questions, explanations, and key status updates directly as visible chat
  messages rather than inside intermediate reasoning/thought blocks or tool
  preambles (which get collapsed into "thoughts for 5s" in Web UI).

## Engineering Discipline

Think before coding:
- State assumptions explicitly. If several interpretations exist, present
  them — don't pick one silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop and ask rather than guess.

Write the minimum code that solves the problem:
- No speculative features, abstractions, configurability, or error handling
  for impossible cases. Test: "Would a senior engineer call this
  overcomplicated?" If yes, simplify.
- Touch only what the task requires: don't improve, refactor, or reformat
  adjacent code; match existing style. Test: every changed line traces
  directly to the request.
- Clean up only your own mess: remove imports/variables your change
  orphaned; leave pre-existing dead code alone (mention it instead).

Verify before declaring victory:
- Turn tasks into checkable goals: "fix the bug" → write a failing test,
  then make it pass; "refactor X" → tests pass before and after.
- Be skeptical of your own "perfect" solution — imagine how it could be
  wrong and verify empirically. Report failures plainly; never declare
  success early.

Local Web App & UI Verification ("Show Me First"):
- When modifying web clients, UI components, HTML templates, CSS, or user-facing services:
  - **Live Server Prerequisite**: Always ensure the dev server is actively running in the background (`IsDaemon: true`) and responsive (`curl -s ...`).
  - **Mandatory Link & URL Artifact**: Create a `<App Name>.url.json` artifact using `http://<hostname>:<PORT>/...` (e.g. `http://kevmoo.c.googlers.com:<PORT>/...`) so it pins in the UI sidebar, and output the clickable preview URL and visual screenshot directly in visible chat.
  - **No Premature Landing Modals**: NEVER trigger an `ask_question` modal asking to commit or ship (`jj ship`) for UI/Web modifications until the user has actively seen the running app and verified the UX behavior. Conclude the turn by presenting the live dev app and inviting the user to inspect/test it.

## GitHub PRs & Commit Messages

- New PRs: `gh pr create -f` when the branch is exactly one commit ahead of
  base; otherwise write explicit `--title`/`--body`.
- Single-commit branches become the PR title/body, so commit messages serve
  both. Subject: imperative, ≤70 chars, specific (`feat(auth): support
  OAuth2 PKCE flow`, never `updates`/`fix bug`). Body: why the change is
  needed, bulleted summary, `Fixes #123` links — no agent meta-commentary
  or tool logs.

## Workspace & Repository Layout

- **Agent Skills Layout (`~/.agents/skills`)**:
  - **No Direct Edits in `~/.agents/skills/`**: `~/.agents/skills/` is the deployed runtime directory for active agent skills. NEVER edit files or directories in `~/.agents/skills/` directly.
  - **Edit Authoritative Source Repositories**: Always locate and modify skills in their respective source repositories:
    - *Personal / OSS Skills*: `~/github/kevmoo/kevmoo_skills/skills/<skill_name>/`
    - *Google3 Skills*: `//depot/google3/experimental/users/kevmoo/skills/...` or `//depot/configs/users/kevmoo/_agents/skills/...`
- **External Repos (`~/github`)**: Sync and open all external GitHub repositories under `~/github`.
  - **Personal Repositories (`github.com/kevmoo`)**: Exclusively clone and nest repositories from my personal GitHub org under `~/github/kevmoo/<repo_name>`.
  - **All Other External Repositories**: Clone directly at the top level of `~/github/<repo_name>` (e.g. `~/github/google-cloud-dart`, `~/github/flutter`, `~/github/googleapis.dart`), never nested under `~/github/<org>/<repo_name>`.
  - `~/github/dart-sdk` has custom agent setup; always check `~/github/dart-sdk/.agents/` when working in that directory.
  - **Sandbox Snapshot Atomic Rename Mitigation**: When executing Dart CLI applications, tests, or scripts in sandboxed environments, if pub pre-compilation fails with `.dart_tool` atomic rename errors (`PathNotFoundException`, `errno = 2`), pass `--no-precompile` (e.g., `dart run --no-precompile <script>` or `dart test --no-precompile`) to bypass executable snapshot caching. Never guess or hallucinate non-existent binary release paths when default tool execution encounters filesystem sandbox limits.
- **Dotfiles (`~/.dotfiles`)**: My home directory (`~/.zshrc`, `~/.config/*`) is managed by a bare repository at `~/.dotfiles`. Whenever inspecting or editing dotfiles in `$HOME`, consult the `personal-dotfiles` skill (`~/.agents/skills/personal-dotfiles/SKILL.md`) for the required Anti-Universe bare-repo protocol and ignore rules.
- **Private Corp Dotfiles (`~/.dotfiles-corp`)**: On gLinux corp machines (e.g. workstations, Cloudtops), internal configurations (like `local.zsh`, `config.local`, and `settings.json`) and corp-specific agent rules are managed via the private bare repository at `~/.dotfiles-corp` and the `dotcorp` CLI.
- **Dart Development & MCP Server Protocol**:
  - **Open-Source Repositories (`~/github/...`)**:
    - **Server**: Exclusively use `dart_oss` MCP tools (`ServerName: "dart_oss"`).
    - **Operational Precedence & Anti-Habit Invariants**:
      - **Symbol Lookup & Signatures**: ALWAYS call `lsp` (`hover`, `resolveWorkspaceSymbol`, `definition`, `signatureHelp`) before running raw text `grep_search` across source trees. Fall back to `grep_search` only if `lsp` returns empty or errors.
      - **Diagnostics**: ALWAYS call `analyze_files` for instant in-memory diagnostics before running standalone CLI test suites or batch analyzers.
      - **Dependencies & Packages**: ALWAYS call `read_package_uris` or `rip_grep_packages` when inspecting third-party package dependencies instead of scanning filesystem caches manually. Use `pub_dev_search` / `pub` to discover packages.
      - **Live Debugging**: Use `dtd` / `hot_reload` / `widget_inspector` for active application debugging.
  - **Google3 Workspaces (`/google/src/...`)**:
    - **Server**: Never invoke `dart_oss` tools. For live debugging/DTD only, use `dart_g3` (`ServerName: "dart_g3"`).
    - **Discipline**: For static analysis, search, editing, and tests in Google3, exclusively use native Google3 tools (`code_search`, `view_file`, `replace_file_content`, `blaze-for-agents`).


