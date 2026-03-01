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
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/github/flutter/bin"
  "$HOME/github/depot_tools"
  "$HOME/.pub-cache/bin"
  "$HOME/.volta/bin"
  $path
)
export VOLTA_HOME="$HOME/.volta"

# 3. Platform Detection & Tool Settings
if [[ "$(uname)" == "Linux" ]]; then
  export CHROME_EXECUTABLE="/var/lib/flatpak/exports/bin/com.google.Chrome"
  # Linux needs aliases for pbcopy/pbpaste (already native on macOS)
  alias pbcopy='wl-copy'
  alias pbpaste='wl-paste'

  # NPM Wrapper to prevent global installs on Bluefin/Silverblue
  # We use eval to prevent the Zsh parser from expanding the 'npm' alias on Mac
  eval '
    unalias npm 2>/dev/null
    function npm {
      if [[ "$*" == *"install -g"* ]] || [[ "$*" == *"--global"* ]]; then
        echo -e "\033[0;33m⚠️  Warning: You are trying to install a global NPM package.\033[0m"
        echo "Consider using npx, volta install, or adding to ~/.Brewfile."
        read -q "confirm?Do you still want to proceed? (y/N) "
        echo
        if [[ $confirm == [yY] ]]; then
          command npm "$@"
        fi
      else
        command npm "$@"
      fi
    }
  '
fi

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
    cat ~/.Brewfile.shared > "$temp_brewfile"
    
    if [[ "$(uname)" == "Darwin" ]]; then
        cat ~/.Brewfile.mac >> "$temp_brewfile"
    elif [[ "$(uname)" == "Linux" ]]; then
        cat ~/.Brewfile.linux >> "$temp_brewfile"
    fi

    echo "Running: brew bundle --cleanup --force"
    brew bundle --file="$temp_brewfile" --cleanup --force
    
    rm "$temp_brewfile"
}

# 6. Modular Configs (Source everything in ~/.zshrc.d)
if [[ -d ~/.zshrc.d ]]; then
  for rc in ~/.zshrc.d/*(N); do
    source "$rc"
  done
fi

# Custom prompt (simple fallback, or use starship if available)
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
else
  PROMPT='%F{cyan}%n@%m%f:%F{blue}%~%f %# '
fi
