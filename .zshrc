# .zshrc - Portable Zsh configuration

# 1. Completion and Zsh options
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # Case-insensitive completion
setopt AUTO_CD          # If a command is a directory, cd into it
setopt HIST_IGNORE_DUPS # Don't record duplicate history entries
setopt SHARE_HISTORY    # Share history between all sessions

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
fi

# 4. Aliases (Shared between platforms)
alias ..='cd ..'
alias ...='cd ../..'
alias a='ls -la'
alias pu='dart pub upgrade'

# 5. Functions
# NPM Wrapper to prevent global installs on Bluefin/Silverblue
npm() {
  if [[ "$*" == *"install -g"* ]] || [[ "$*" == *"--global"* ]]; then
    echo -e "\033[0;33m⚠️  Warning: You are trying to install a global NPM package.\033[0m"
    echo "Consider using 'npx', 'volta install', or adding to ~/.Brewfile."
    read -q "confirm?Do you still want to proceed? (y/N) "
    echo # Move to a new line after read
    if [[ $confirm == [yY] ]]; then
      command npm "$@"
    fi
  else
    command npm "$@"
  fi
}

brewall() {
    echo "Running: brew update"
    brew update
    
    echo "Running: brew bundle --global --file=~/.Brewfile.shared"
    brew bundle --global --file=~/.Brewfile.shared
    
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "Running: brew bundle --global --file=~/.Brewfile.mac"
        brew bundle --global --file=~/.Brewfile.mac
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "Running: brew bundle --global --file=~/.Brewfile.linux"
        brew bundle --global --file=~/.Brewfile.linux
    fi

    echo "Running: brew bundle cleanup --global --file=~/.Brewfile.shared"
    # Note: Cleanup might need care with multiple files, usually best to do it manually or via a combined temp file
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
