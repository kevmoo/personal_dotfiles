# ~/.zshrc.d/mac-local.zsh

# Mac-specific PATH additions (Zsh unique array handles deduplication)
typeset -U path
path=(
  "$HOME/.jetski/jetski/bin"
  "$HOME/.pub-cache/bin"
  "$HOME/bin"
  "$HOME/github/depot_tools"
  "$HOME/github/flutter/bin"
  "$HOME/.cargo/bin"
  $path
)

# Environment Variables
export EDITOR="subl -w"
export RBE=1
export RBE_cache_dir='/tmp/rbe'

# Increase open file descriptor limit
ulimit -n 10240
