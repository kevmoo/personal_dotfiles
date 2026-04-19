# .zshrc - Portable Zsh configuration

# 1. Completion and Zsh options (Interactive only)
if [[ -t 1 ]]; then
  # Ensure XDG directories exist
  mkdir -p "$HOME/.cache/zsh" "$HOME/.local/state/zsh"
  export ZSH_COMPDUMP="$HOME/.cache/zsh/zcompdump"
  autoload -Uz compinit && compinit -d "$ZSH_COMPDUMP"
  zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # Case-insensitive completion
  zstyle ':completion:*' menu select                 # Arrow-key selection menu
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" # Match LS_COLORS
  zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %d --%f' # Section headers

  setopt AUTO_CD          # If a command is a path, CD to it
  setopt HIST_IGNORE_DUPS # Don't record duplicate history
  setopt SHARE_HISTORY    # Share history between sessions
  export HISTFILE="$HOME/.local/state/zsh/history"
  export HISTSIZE=10000
  export SAVEHIST=10000

  # Word navigation (make Ctrl-W delete by path segments, not just whitespace)
  autoload -Uz select-word-style
  select-word-style bash
  # Default WORDCHARS often includes / - removing it makes / a word boundary
  export WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
fi


# 2. Path Management (Zsh specific: $path array automatically syncs with $PATH)
typeset -U path # Keep path array unique
local -a candidates=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/github/flutter/bin"
  "$HOME/github/depot_tools"
  "$HOME/.pub-cache/bin"
)
export NODE_REPL_HISTORY="$HOME/.local/state/node/history"
export PYTHON_HISTORY="$HOME/.local/state/python/history"
export LESSHISTFILE="$HOME/.local/state/less/history"

# 4. Aliases (Shared between platforms)
alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
alias ..='cd ..'
alias ...='cd ../..'
alias a='ls -la --no-git'
alias pu='dart pub upgrade'
alias pbr='dart run build_runner'

# tmux session management
# 'tm' will attach to a session named "main", or create it if it doesn't exist.
# This allows you to share the same session between local and SSH.
tm() {
  tmux attach-session -t main 2>/dev/null || tmux new-session -s main
}
alias t='tm'

# Auto-attach to tmux on SSH login
# Only if we are in an interactive shell, not already in tmux, and connecting via SSH
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
  if [[ -z "$TMUX" && -t 1 ]]; then
    tm
  fi
fi

# 5. Functions
brewall() {
    echo "Running: brew update"
    brew update
    
    local temp_brewfile=$(mktemp)
    cat ~/.config/brew/Brewfile.shared > "$temp_brewfile"
    
    if [[ "$(uname)" == "Darwin" ]]; then
        cat ~/.config/brew/Brewfile.mac >> "$temp_brewfile"
    elif [[ "$(uname)" == "Linux" ]]; then
        cat ~/.config/brew/Brewfile.linux >> "$temp_brewfile"
    fi

    echo "Running: brew bundle --upgrade --cleanup --force --verbose"
    brew bundle --file="$temp_brewfile" --upgrade --cleanup --force --verbose
    
    # brew bundle --upgrade only checks for upgrades on formulas listed in the Brewfile.
    # We call brew upgrade here to ensure that transitive dependencies (like imagemagick, 
    # libomp, or luajit) are also kept up-to-date.
    echo "Running: brew upgrade"
    brew upgrade

    # Clean up old versions of formulas and clear the cache.
    echo "Running: brew cleanup"
    brew cleanup
    
    rm "$temp_brewfile"
}

# 6. Modular Configs (Source everything in ~/.config/zsh/rc.d)
if [[ -d ~/.config/zsh/rc.d ]]; then
  for rc in ~/.config/zsh/rc.d/*(N); do
    # Skip platform-specific files that don't match the current OS
    if [[ "$rc" == *"mac-local.zsh"* && "$(uname)" != "Darwin" ]]; then continue; fi
    if [[ "$rc" == *"linux-local.zsh"* && "$(uname)" != "Linux" ]]; then continue; fi

    source "$rc"
  done
fi

# 7. Finalize Environment
# Filter candidates and update $path
local -a missing=()
for dir in $candidates; do
  if [[ -d "$dir" ]]; then
    path=("$dir" $path)
  else
    missing+=("$dir")
  fi
done

# Inform the user about missing paths (subtly)
if (( ${#missing} > 0 )); then
  # Only show this in interactive shells
  if [[ -t 1 ]]; then
    echo -e "\033[0;34mℹ️  Note: Some configured paths are missing: \033[0;33m${missing[*]}\033[0m"
  fi
fi

# 8. Initialize Tool Managers
# mise: universal tool manager
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# Custom prompt (simple fallback, or use starship if available)
if (( $+commands[starship] )) && [[ "$TERM" != "dumb" ]]; then
  eval "$(starship init zsh)"
else
  PROMPT='%F{cyan}%n@%m%f:%F{blue}%2~%f %# '
fi
