# ~/.zshrc.d/mac-local.zsh

# Mac-specific PATH additions
candidates+=(
  "/opt/homebrew/share/google-cloud-sdk/bin"
  "/opt/homebrew/opt/python@3.12/bin"
  "$HOME/.jetski/jetski/bin"
  "$HOME/.cargo/bin"
)

# Environment Variables
export CLOUDSDK_PYTHON="/opt/homebrew/opt/python@3.12/bin/python3.12"
export EDITOR="subl -w"
export RBE=1
export RBE_cache_dir='/tmp/rbe'

# Increase open file descriptor limit
ulimit -n 10240
