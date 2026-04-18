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
A custom Zsh function is included in `~/.zshrc` to sync your environment:
```bash
brewall  # Updates brew and installs tools from shared + platform-specific files
```

---

## 🌌 Preventing "The Listing of the Universe"
Because the working tree is your entire `$HOME` directory, a standard `git status` would attempt to list every single untracked file you own—downloads, cache, temporary files, everything. We call this "Listing the Universe."

To prevent this, we employ a **double-layered defense**:

1.  **Untracked Filter:** We tell Git to ignore untracked files by default in the local config:
    ```bash
    dot config --local status.showUntrackedFiles no
    ```
2.  **Global "Ignore All":** We use a `*` wildcard in `~/.dotfiles/info/exclude` to ignore everything by default, and then explicitly "un-ignore" only the files we want to track (e.g., `!.zshrc`).

This ensure that `dot status` remains lightning-fast and only shows changes to files you have **explicitly** chosen to track. It's the difference between a curated collection and a digital hoard.

---

## 🧩 The Critical Un-Trackable State

**WARNING:** Since `info/exclude` itself cannot be tracked, you must update the documentation below whenever you add a new "un-ignored" file.
Because this is a bare repository with the working tree at `$HOME`, some critical configuration lives inside the `~/.dotfiles/` directory itself and **cannot be tracked** by Git. When setting up a new machine, you must manually recreate these:

1.  **Untracked Filter:** To keep `dot status` clean, ignore untracked files:
    ```bash
    dot config --local status.showUntrackedFiles no
    ```
    - Add `!.config/` to track config files.
    - Add `!.local/` to track local binaries.
2.  **Secret Exclusion:** Add `.zshrc.d/secrets.zsh` to the local Git exclude list:
    - Add `!.local/bin/brew-check` to the local Git exclude list to track the brew audit script.
    ```bash
    echo ".zshrc.d/secrets.zsh" >> $HOME/.dotfiles/info/exclude
    ```
3.  **Secrets Content:** Manually recreate `~/.zshrc.d/secrets.zsh` with your API keys and private tokens. This file is sourced by `~/.zshrc` but ignored by Git.

---

## ⚡ Shell Power Tools
This environment is enhanced with modern CLI replacements:

*   **`zoxide` (z)**: A smarter `cd` command. Use `z <fragment>` or `zi` for interactive selection.
*   **`fzf`**: Fuzzy finder for history (`Ctrl+r`) and files (`Ctrl+t`).
*   **`eza`**: A modern `ls` (aliased to `ls` and `a`). Features icons and Git status integration.
*   **`bat`**: A modern `cat` with syntax highlighting and line numbers.
*   **`tmux`**: Terminal multiplexer with custom navigation and `|`/`-` splits. See [cheat sheet](.config/kevmoo-fyi/tmux.md).

---

## 💎 Why This Approach?

*   **Zero Symlinks**: Files live in their natural locations (e.g., `~/.zshrc`,
    `~/.gitconfig`). You don't need to manage a complex tree of symlinks or use
    tools like GNU Stow.
*   **Gemini Settings**: Your coding style and preferences are tracked in
    [.gemini/GEMINI.md](.gemini/GEMINI.md).
*   **Native Git Experience**: Since `dot` is just a standard Git command with
    specific flags, all your existing Git knowledge applies (`dot status`,
    `dot add`, `dot commit`, `dot diff`, etc.).
*   **Portable & Lightweight**: This works on any system with Git installed. No
    Python, Ruby, or Node.js dependencies are required.
*   **Clean Workflow**: Only files you explicitly `dot add` are tracked. The
    rest of your home directory remains invisible to Git.

---

## 🛠 Common Workflows

### Tracking a new config file
```bash
dot add ~/.zshrc
dot commit -m "Add zshrc to dotfiles"
```

### Reviewing changes
```bash
dot status
dot diff
```

### Syncing with a remote
```bash
dot push origin main
dot pull origin main
```

### Initial Setup on a New Machine
1. **Clone the repo** as a bare repository:
   ```bash
   git clone --bare <your-repo-url> $HOME/.dotfiles
   ```
2. **Define the alias** in your current shell session:
   ```bash
   alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
   ```
3. **Checkout the content** into your home directory. If you have existing
   configuration files, this may fail. To resolve it, back them up first:
   ```bash
   mkdir -p ~/.dotfiles-backup && \
   dot checkout 2>&1 | grep -E "^\s+\." | awk '{print $1}' | \
   xargs -I{} mv $HOME/{} ~/.dotfiles-backup/{} && \
   dot checkout
   ```

### 🏁 Post-Install Steps
After the initial checkout and `brewall`, perform these final steps:

1.  **Set Default Shell**: `chsh -s /bin/zsh`
2.  **Initialize Volta**: `volta install node@latest`
3.  **Initialize Rust**: `rustup-init` (follow the prompts)
4.  **Verify Setup**: Open a new terminal and ensure the Starship prompt appears.

---

## 📜 The Odyssey
Curious how this setup came to be? Check out the [Great Dotfile Migration History](.config/kevmoo-fyi/dot_file_history.md) for the full story.
