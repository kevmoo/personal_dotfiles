# .zshrc - Portable Zsh configuration

# 1. Completion and Zsh options
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # Case-insensitive completion
zstyle ':completion:*' menu select                 # Arrow-key selection menu
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" # Match LS_COLORS
zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %d --%f' # Section headers

setopt AUTO_CD          # If a command is a path, CD to it
setopt HIST_IGNORE_DUPS # Don't record duplicate history
setopt SHARE_HISTORY    # Share history between sessions

# Word navigation (make Ctrl-W delete by path segments, not just whitespace)
autoload -Uz select-word-style
select-word-style bash
# Default WORDCHARS often includes / - removing it makes / a word boundary
export WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'


# 2. Path Management (Zsh specific: $path array automatically syncs with $PATH)
typeset -U path # Keep path array unique
local -a candidates=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/github/flutter/bin"
  "$HOME/github/depot_tools"
  "$HOME/.pub-cache/bin"
  "$HOME/.volta/bin"
)
export VOLTA_HOME="$HOME/.volta"

# 4. Aliases (Shared between platforms)
alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
alias ..='cd ..'
alias ...='cd ../..'
alias a='ls -la'
alias pu='dart pub upgrade'

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

    echo "Running: brew bundle --cleanup --force"
    brew bundle --file="$temp_brewfile" --cleanup --force
    
    rm "$temp_brewfile"
}

# 6. Modular Configs (Source everything in ~/.zshrc.d)
if [[ -d ~/.zshrc.d ]]; then
  for rc in ~/.zshrc.d/*(N); do
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

# Custom prompt (simple fallback, or use starship if available)
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
else
  PROMPT='%F{cyan}%n@%m%f:%F{blue}%~%f %# '
fi
