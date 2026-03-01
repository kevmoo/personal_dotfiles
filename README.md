# 📂 Managing Dotfiles with a Bare Git Repository

This setup allows for managing configuration files (dotfiles) directly in the
`$HOME` directory using Git, without the need for symlinks, specialized
management tools, or messy directory structures.

## 🚀 The Implementation
The core of the system is a **bare Git repository** located at `~/.dotfiles/`.
Unlike a standard repository, a bare repo doesn't have a default working
directory. We manually point its "working tree" to `$HOME` using a simple shell
alias.

### The Magic Alias
Add this to your `.zshrc`:
```bash
alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

## ⚙️ Key Configuration
To prevent Git from showing every untracked file in your home directory (which
would make `dot status` unusable), we configure the repository to ignore
untracked files by default:

```bash
dot config --local status.showUntrackedFiles no
```

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
4. **Silence untracked files**:
   ```bash
   dot config --local status.showUntrackedFiles no
   ```
