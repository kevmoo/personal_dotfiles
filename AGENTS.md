# Global Agent Instructions

Shared by all coding agents (Claude Code, Gemini CLI) via symlinks to
~/AGENTS.md. Hard boundaries first; working style after. Git/GitHub safety
is also enforced by each agent's permission settings — these rules state intent.

## Hard Boundaries

- **Version control writes**: never commit, push, amend, rebase, or reset
  unless I explicitly asked in this conversation. Instead, stop and ask (see
  Approvals below) with a summary of modified files. Reason: I freeze code
  into repository history myself; unwanted commits are expensive to unwind.
- **GitHub writes** (issues, PRs, comments, releases) are outward-facing:
  ask before every single one. One approval covers one action; it never
  carries over to the next.
- **github.com URLs**: always read via the `gh` CLI, never generic URL
  fetchers (they get blocked or return login pages).
- Read-only inspection (`grep`, `find`, `git status/diff/log/show`,
  `gh ... view/list`) is always safe — run it eagerly, without asking.

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
- **Clickable Links (Files & URLs)**: Whenever referencing any file, directory, or web resource (HTTP/HTTPS URLs, CLs, PRs, Go links) in the conversation, **always** format it as a clickable Markdown link (using `file://` with absolute paths for local files). Never use plain backticks for filenames or web URLs.
  - To avoid ambiguity or confusion (e.g., distinguishing between different `BUILD` files or common names), include enough preceding path components in the link text (e.g., [src/main.dart](file:///absolute/path/to/src/main.dart) instead of `[main.dart]`).
  - **CRITICAL**: Do NOT wrap URLs, link text, or entire markdown links in backticks (e.g., `\``). Doing so turns the link into a literal code block and breaks clickability in the chat UI.
  - *Correct* (renders as a clickable link): [subdir/filename.md](file:///absolute/path/to/subdir/filename.md), [cl/123456789](http://cl/123456789), [PR #123](https://github.com/org/repo/pull/123)
  - *Incorrect* (will NOT render as a link): `` `filename.md` ``, `` `https://github.com/...` ``
  - *Incorrect* (wrapping the entire link in backticks will NOT render as a link): `` `[subdir/filename.md](file:///absolute/path/to/subdir/filename.md)` ``
  - *Incorrect* (wrapping the link text in backticks will NOT render as a link): `` [`subdir/filename.md`](file:///absolute/path/to/subdir/filename.md) ``
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

## GitHub PRs & Commit Messages

- New PRs: `gh pr create -f` when the branch is exactly one commit ahead of
  base; otherwise write explicit `--title`/`--body`.
- Single-commit branches become the PR title/body, so commit messages serve
  both. Subject: imperative, ≤70 chars, specific (`feat(auth): support
  OAuth2 PKCE flow`, never `updates`/`fix bug`). Body: why the change is
  needed, bulleted summary, `Fixes #123` links — no agent meta-commentary
  or tool logs.

## Workspace & Repository Layout

- **External Repos (`~/github`)**: Sync and open all external GitHub repositories under `~/github`.
  - Repositories from my personal GitHub org (`github.com/kevmoo`) live under `~/github/kevmoo/<repo_name>`.
  - `~/github/dart-sdk` has custom agent setup; always check `~/github/dart-sdk/.agents/` when working in that directory.
  - **Dart SDK for External Repos**: When running Dart tooling (`dart test`, `dart run`, `pub get`) inside any repository under `~/github` (excluding `~/github/dart-sdk`), **always invoke Dart via `~/github/flutter/bin/dart`** (or prepend `~/github/flutter/bin` to `PATH`). Never invoke the system `/usr/bin/dart`, which is linked to internal Google3 edge builds and breaks public SemVer constraints.
  - **Sandbox Snapshot Atomic Rename Mitigation**: When executing Dart CLI applications, tests, or scripts in sandboxed environments, if pub pre-compilation fails with `.dart_tool` atomic rename errors (`PathNotFoundException`, `errno = 2`), pass `--no-precompile` (e.g., `dart run --no-precompile <script>` or `dart test --no-precompile`) to bypass executable snapshot caching. Never guess or hallucinate non-existent binary release paths when default tool execution encounters filesystem sandbox limits.
- **Dotfiles (`~/.dotfiles`)**: My home directory (`~/.zshrc`, `~/.config/*`) is managed by a bare repository at `~/.dotfiles`. Whenever inspecting or editing dotfiles in `$HOME`, consult the `personal-dotfiles` skill (`~/.agents/skills/personal-dotfiles/SKILL.md`) for the required Anti-Universe bare-repo protocol and ignore rules.
- **Private Corp Dotfiles (`~/.dotfiles-corp`)**: On gLinux corp machines (e.g. workstations, Cloudtops), internal configurations (like `local.zsh`, `config.local`, and `settings.json`) and corp-specific agent rules are managed via the private bare repository at `~/.dotfiles-corp` and the `dotcorp` CLI.

