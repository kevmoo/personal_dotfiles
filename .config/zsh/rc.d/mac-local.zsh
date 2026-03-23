# ~/.zshrc.d/mac-local.zsh

# Mac-specific PATH additions
candidates+=(
  "/opt/homebrew/share/google-cloud-sdk/bin"
  "$HOME/.jetski/jetski/bin"
  "$HOME/.cargo/bin"
)

# Environment Variables
export EDITOR="code --wait"
export RBE=1
export RBE_cache_dir='/tmp/rbe'

# Increase open file descriptor limit
ulimit -n 10240
