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
2.  **Restore the Exclude File**:
    The tracked version of your ignore rules lives at `.config/dot/info-exclude.example`. Restore it manually:
    ```bash
    mkdir -p ~/.dotfiles/info
    dot show HEAD:.config/dot/info-exclude.example > ~/.dotfiles/info/exclude
    ```
3.  **Checkout Content**:
    ```bash
    dot checkout
    ```
4.  **Validate**:
    ```bash
    dot-check-ignores
    ```

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
