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
- **Clickable File Links**: Whenever referencing any file (newly created, modified, or inspected) or directory in the conversation, **always** format it as a clickable Markdown link using the `file://` scheme with its absolute local path. Do not use plain backticks for filenames.
  - To avoid ambiguity or confusion (e.g., distinguishing between different `BUILD` files or common names), include enough preceding path components in the link text (e.g., [src/main.dart](file:///absolute/path/to/src/main.dart) instead of `[main.dart]`).
  - **CRITICAL**: Do NOT wrap the link text, nor the entire markdown link, in backticks (e.g., `\``). Doing so turns the link into a code literal block and prevents rendering in the chat UI.
  - *Correct* (renders as a clickable link): [subdir/filename.md](file:///absolute/path/to/subdir/filename.md)
  - *Incorrect* (will NOT render as a link): `` `filename.md` `` or `` `subdir/filename.md` ``
  - *Incorrect* (wrapping the entire link in backticks will NOT render as a link): `` `[subdir/filename.md](file:///absolute/path/to/subdir/filename.md)` ``
  - *Incorrect* (wrapping the link text in backticks will NOT render as a link): `` [`subdir/filename.md`](file:///absolute/path/to/subdir/filename.md) ``

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
- **Dotfiles (`~/.dotfiles`)**: My home directory (`~/.zshrc`, `~/.config/*`) is managed by a bare repository at `~/.dotfiles`. Whenever inspecting or editing dotfiles in `$HOME`, consult the `personal-dotfiles` skill (`~/.agents/skills/personal-dotfiles/SKILL.md`) for the required Anti-Universe bare-repo protocol and ignore rules.
- **Private Corp Dotfiles (`~/.dotfiles-corp`)**: On gLinux corp machines (e.g. workstations, Cloudtops), you must clone your private Git-on-Borg dotfiles repository to backup internal configs (like `local.zsh`, `config.local`, and `settings.json`):
  `git clone --bare sso://user/kevmoo/dotfiles-corp ~/.dotfiles-corp`
  And configure it to hide untracked files:
  `git --git-dir=$HOME/.dotfiles-corp/ --work-tree=$HOME config --local status.showUntrackedFiles no`
  All private files (local Zsh configs, Git profiles, local safety settings) are managed via the `dotcorp` command line script.

