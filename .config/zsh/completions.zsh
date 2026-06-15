# ~/.config/zsh/completions.zsh - Optimized Zsh Completion Configuration
# Native Zsh APIs, zero external dependencies, high performance.

# Ensure completion and state directories exist without spawning a process in 99% of runs
[[ -d "$HOME/.cache/zsh/cache" && -d "$HOME/.local/state/zsh" ]] || mkdir -p "$HOME/.cache/zsh/cache" "$HOME/.local/state/zsh"

export ZSH_COMPDUMP="$HOME/.cache/zsh/zcompdump"

# Detect Homebrew and enable completions if available
typeset -U fpath
local brew_prefix
if [[ -x /opt/homebrew/bin/brew ]]; then
  brew_prefix="/opt/homebrew"
elif [[ -x /usr/local/bin/brew ]]; then
  brew_prefix="/usr/local"
elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  brew_prefix="/home/linuxbrew/.linuxbrew"
elif (( $+commands[brew] )); then
  brew_prefix=$(brew --prefix)
fi

if [[ -n "$brew_prefix" ]]; then
  local brew_fpath="$brew_prefix/share/zsh/site-functions"
  if [[ -d "$brew_fpath" ]]; then
    fpath=("$brew_fpath" $fpath)
  fi
fi

# Highly optimized compinit loading (daily check + background compilation)
autoload -Uz compinit
if [[ -n "$ZSH_COMPDUMP"(N.m-1) ]]; then
  # Dump file is less than 24 hours old: load instantly, skipping security checks
  compinit -C -d "$ZSH_COMPDUMP"
else
  # Dump file is missing or old: perform full audit and rebuild
  compinit -d "$ZSH_COMPDUMP"
  # Compile the dump file to a binary (.zwc) in the background for even faster subsequent loads
  zcompile "$ZSH_COMPDUMP"
fi

# Enable completion caching for slow commands (brew, apt, etc.)
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.cache/zsh/cache"

# Gold Standard Matcher: Case-insensitive, hyphen/underscore-insensitive, and partial completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z-_}={A-Za-z_-}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Premium Menu and Color Selection
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Group completions by category (e.g. commands, files, options)
zstyle ':completion:*' group-name ''
zstyle ':completion:*:*:*:*:descriptions' format '%F{green}── %d ──%f'

# Beautiful warnings and messages
zstyle ':completion:*:messages' format '%F{purple}── %d ──%f'
zstyle ':completion:*:warnings' format '%F{red}⚠️  No matches for: %d%f'
