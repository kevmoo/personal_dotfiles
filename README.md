# 📂 Managing Dotfiles with a Bare Git Repository

This setup allows for managing configuration files (dotfiles) directly in the
`$HOME` directory using Git, without the need for symlinks, specialized
management tools, or messy directory structures.

## 🚀 The Implementation
The core of the system is a **bare Git repository** located at `~/.dotfiles/`.
Unlike a standard repository, a bare repo doesn't have a default working
directory. We manually point its "working tree" to `$HOME` using a simple shell
alias.

### The Magic Alias & Shell Modularity
Add this to your `.zshrc`:
```bash
alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```
The shell automatically sources all `*.zsh` files in `~/.zshrc.d/`. Modular configurations include:
*   **`shell-power.zsh`**: (Tracked) Common interactive enhancements (fzf, zoxide, eza).
*   **`mac-local.zsh`**: (Tracked) Mac-specific PATH and environment overrides.
*   **`secrets.zsh`**: (Untracked) Private API keys.

### 🖥️ Native Git & IDE GUI Support (Gitdir Proxy Workspace)
While the `dot` alias works great in the terminal, IDEs (like VS Code) and Git GUIs (like LazyGit or Sourcetree) expect standard Git repository structures. To make normal `git` commands and GUIs work seamlessly inside a dedicated workspace folder (e.g., `~/github/kevmoo/personal_dotfiles/`):

1.  **Configure the bare repo's working tree**:
    Ensure `core.worktree` points to `$HOME` and `core.bare` is `false` in `~/.dotfiles/config`:
    ```bash
    dot config --local core.worktree "$HOME"
    dot config --local core.bare false
    ```
2.  **Create a proxy workspace directory**:
    Create a folder wherever you want your IDE workspace to live, containing a plain text `.git` file with a `gitdir:` pointer to your bare repository:
    ```bash
    mkdir -p ~/github/kevmoo/personal_dotfiles
    echo "gitdir: $HOME/.dotfiles" > ~/github/kevmoo/personal_dotfiles/.git
    ```

Now, running standard `git status`, `git diff`, or opening Git GUIs inside `~/github/kevmoo/personal_dotfiles` automatically redirects to `~/.dotfiles` and operates across your entire home directory.

---

## 🍺 Package Management (Homebrew)
This setup uses modular Brewfiles to share configuration between Linux and macOS:

*   **`~/.Brewfile.shared`**: CLI tools used on both platforms (e.g., `bat`, `eza`, `fzf`).
*   **`~/.Brewfile.mac`**: macOS-specific GUI apps and development tools.
*   **`~/.Brewfile.linux`**: Linux-specific Flatpaks and system fonts.

### The `brewall` command
A custom Zsh function is included in `~/.zshrc` to sync your environment.

### 🛠 Audit Tools
*   **`brew-check`**: Lists Homebrew packages installed but NOT in your Brewfiles.
*   **`dot-check-ignores`**: Validates that your untrackable `~/.dotfiles/info/exclude` is in sync with the tracked version in `.config/dot/info-exclude.example`.

---

## 🌌 Preventing "The Listing of the Universe"
Because the working tree is your entire `$HOME` directory, a standard `git status` would attempt to list every single untracked file you own. We employ a **double-layered defense**:

1.  **Untracked Filter:** We tell Git to ignore untracked files by default:
    ```bash
    dot config --local status.showUntrackedFiles no
    ```
2.  **Global "Ignore All":** We use a `*` wildcard in `~/.dotfiles/info/exclude` to ignore everything by default, and then explicitly "un-ignore" only the files we want to track (e.g., `!.zshrc`).

---

## 🧩 The Critical Un-Trackable State

**WARNING:** Since `info/exclude` itself cannot be tracked by Git, you must manually recreate your "un-ignore" rules when setting up a new machine.

### Initial Setup on a New Machine
1.  **Clone & Alias**:
    ```bash
    git clone --bare <your-repo-url> $HOME/.dotfiles
    alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
    ```
2.  **Configure Core Worktree & Proxy Workspace** (Optional, for IDE/GUI support):
    ```bash
    dot config --local core.worktree "$HOME"
    dot config --local core.bare false
    mkdir -p ~/github/kevmoo/personal_dotfiles
    echo "gitdir: $HOME/.dotfiles" > ~/github/kevmoo/personal_dotfiles/.git
    ```
3.  **Restore the Exclude File**:
    The tracked version of your ignore rules lives at `.config/dot/info-exclude.example`. Restore it manually:
    ```bash
    mkdir -p ~/.dotfiles/info
    dot show HEAD:.config/dot/info-exclude.example > ~/.dotfiles/info/exclude
    ```
4.  **Checkout Content**:
    ```bash
    dot checkout
    ```
5.  **Validate**:
    ```bash
    dot-check-ignores
    ```
6.  **Wire Up Agent Skills**: `upkeep update skills` links every skill in
    `~/.agents/skills` into `~/.claude/skills` (Gemini reads
    `~/.agents/skills` directly).

### Syncing an Existing Machine
1.  **Check for local changes**: `dot fetch && dot status -sb --untracked=no`. If only
    `.agents/` files are modified, a local `npx skills update` re-synced
    skills another machine already pushed. Confirm the lock hashes match
    (`dot diff @{u} -- .agents/.skill-lock.json` shows only `updatedAt` or
    added/removed skills), then discard: `dot checkout -- .agents`.
2.  **Pull**: `dot pull --ff-only`.
3.  **Exclude rules**: `dot-check-ignores`. If out of sync, restore with
    `cp ~/.config/dot/info-exclude.example ~/.dotfiles/info/exclude`.
4.  **Skills**: `upkeep update skills` re-links new skills into
    `~/.claude/skills` and prunes dangling links for retired ones (a plain
    `dot pull` does not). It also runs `npx skills update`; if that changes
    anything under `.agents/`, commit and push it right away (see
    [`.agents/README.md`](.agents/README.md)) so other machines don't
    diverge.

---

## ⚡ Shell Power Tools
This environment is enhanced with modern CLI replacements: `zoxide`, `fzf`, `eza`, `bat`, and `tmux`.

---

## 💎 Why This Approach?
*   **Zero Symlinks**: Files live in their natural locations.
*   **Native Git Experience**: It's just Git.
*   **Clean Workflow**: Only explicitly tracked files are visible.

---

## 📜 The Odyssey
Curious how this setup came to be? Check out the [Great Dotfile Migration History](.config/kevmoo-fyi/dot_file_history.md) for the full story.
