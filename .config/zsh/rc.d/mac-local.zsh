# ~/.zshrc.d/mac-local.zsh

# Mac-specific PATH additions
candidates+=(
  "$HOME/.jetski/jetski/bin"
  "$HOME/.cargo/bin"
  "$HOME/.antigravity/antigravity/bin"
  "$HOME/.antigravity-ide/antigravity-ide/bin"
)

# Environment Variables
export EDITOR="codium --wait"
export RBE=1
export RBE_cache_dir='/tmp/rbe'

# Increase open file descriptor limit
ulimit -n 10240

# Aliases
alias corp-ssh='gcertstatus --check_remaining=1h --quiet || gcert; ssh kevmoo.c.googlers.com'
