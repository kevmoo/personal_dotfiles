# ~/.config/zsh/completions.zsh - Optimized Zsh Completion Configuration
# Native Zsh APIs, zero external dependencies, high performance.

# Ensure completion and state directories exist without spawning a process in 99% of runs
[[ -d "$HOME/.cache/zsh/cache" && -d "$HOME/.local/state/zsh" ]] || mkdir -p "$HOME/.cache/zsh/cache" "$HOME/.local/state/zsh"

export ZSH_COMPDUMP="$HOME/.cache/zsh/zcompdump"

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
