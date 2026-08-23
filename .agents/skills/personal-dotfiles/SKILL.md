---
name: personal-dotfiles
description: Guidelines, Anti-Universe Git protocol, bare repository setup, and parent directory ignore overrides for managing the personal_dotfiles repository. Use whenever working on dotfiles, ~/.zshrc, ~/.config, or the personal_dotfiles repository.
---

# 🌌 THE "~/.dotfiles" HOME DIRECTORY PROTOCOL

> [!WARNING]
> **SCOPE BOUNDARY:** The instructions below are **ONLY applicable** when you
> are working with files tracked by the **personal_dotfiles** repository
> (metadata in `~/.dotfiles`). If you are working on any other project,
> library, or application, **DISREGARD AND IGNORE everything below this line.**

### 🌌 The "Anti-Universe" Git Protocol
When working within the **personal_dotfiles** repository (via the `dot` command):
- **Ignore by Default:** We employ a "double-layered" defense against listing
  the entire home directory. `status.showUntrackedFiles` is set to `no`, and
  `~/.dotfiles/info/exclude` uses a `*` wildcard.
- **No FSMonitor:** The `core.fsmonitor` daemon is disabled for this
  repository as it causes hangs when monitoring the entire home directory.

#### How to Add New Files (The Ignore Overrides)
Because everything in `$HOME` is ignored by default via the `*` rule, Git's
default behavior prevents descending into ignored directories to find
exceptions. You MUST use one of the two solutions below to track new files:

*   **Solution 1: Force Add (Recommended for deep paths)**
    The easiest and most reliable way to track a new file deeply nested in an
    ignored directory is to bypass the ignore list and force-add it directly
    to the index:
    ```bash
    git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME add -f path/to/file
    ```
    Once a file is tracked in the index, Git will continue to monitor it for
    modifications, even if it technically matches an ignore pattern.

*   **Solution 2: Explicitly Un-ignore All Parent Directories**
    If you prefer to maintain the `~/.dotfiles/info/exclude` file, you MUST
    explicitly un-ignore every single parent directory down to the file, using
    trailing slashes to tell Git to descend. For example, to track a file under
    `.config/git/hooks/`:
    ```text
    *
    !.config/
    !.config/git/
    !.config/git/hooks/
    !.config/git/hooks/*
    ```

### 🌌 Repository Architecture: Bare Dotfiles + Gitdir Proxy
AI coding assistants and IDEs (like VS Code) working inside the proxy workspace
`~/github/kevmoo/personal_dotfiles` interact with Git via native redirection:
- The `.git` entry in the proxy workspace is a plain text file containing
  `gitdir:` pointing to the true Git metadata database at `~/.dotfiles`.
- The true Git database (`~/.dotfiles`) has `core.worktree` configured to
  `$HOME`.
- Running standard `git status`, `git diff`, or `git add` from inside the proxy
  workspace seamlessly operates on tracked dotfiles across the entire home
  directory (`~/.zshrc`, `~/.config/*`, etc.).

**Important Constraints:**
1. **Ignore Rules:** By default, `$HOME` is ignored via a `*` wildcard in
   `~/.dotfiles/info/exclude` to prevent listing untracked files across the
   entire OS.
2. **Adding New Files:** To track a newly created file in `$HOME`, you must
   either use `git add -f <path>` or explicitly un-ignore its parent directories
   in `~/.dotfiles/info/exclude`.
3. **Scope Boundary:** Do not modify unrelated files in `$HOME` outside the
   requested task.

### 🐚 Shell & Prompt Layout
- **Entry Point:** `~/.zshrc`
- **Modular Configs:** `~/.config/zsh/rc.d/*.zsh`
  - `shell-power.zsh`: Enhancements (fzf, zoxide, eza).
  - `mac-local.zsh` / `linux-local.zsh`: OS-specific overrides.
- **Prompt:** Managed by `starship` via `~/.config/starship.toml`.
