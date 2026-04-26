# ~/.zshrc.d/mac-local.zsh

# Mac-specific PATH additions
candidates+=(
  "$HOME/.jetski/jetski/bin"
  "$HOME/.cargo/bin"
)

# Environment Variables
export EDITOR="codium --wait"
export RBE=1
export RBE_cache_dir='/tmp/rbe'

# Increase open file descriptor limit
ulimit -n 10240
