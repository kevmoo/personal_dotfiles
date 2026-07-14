# ~/.zshrc.d/mac-local.zsh

# Mac-specific PATH additions
candidates+=(
  "$HOME/.jetski/jetski/bin"
  "$HOME/.cargo/bin"
  "$HOME/.antigravity/antigravity/bin"
  "$HOME/.antigravity-ide/antigravity-ide/bin"
  "$HOME/Library/Application Support/Dart/install/bin"
)

# Environment Variables
export EDITOR="codium --wait"
export RBE=1
export RBE_cache_dir='/tmp/rbe'

# Increase open file descriptor limit
ulimit -n 10240

# Aliases
alias corp-ssh='gcertstatus --check_remaining=1h --quiet || gcert; ssh kevmoo.c.googlers.com'

# Tunnels
corp-tunnel() {
  local local_port=${1:-8080}
  local remote_port=${2:-$local_port}

  if nc -z localhost "$local_port" >/dev/null 2>&1; then
    echo "Error: Local port $local_port is already in use by:"
    lsof -i :"$local_port"
    return 1
  fi

  gcertstatus --check_remaining=1h --quiet || gcert
  echo "Establishing tunnel to kevmoo.c.googlers.com (local $local_port -> remote $remote_port)..."
  echo "Press Ctrl+C to stop."

  # Handle Ctrl+C cleanly
  trap 'echo "\nStopping tunnel..."; return 1' INT

  while true; do
    ssh -N \
      -o ServerAliveInterval=15 \
      -o ServerAliveCountMax=3 \
      -o ExitOnForwardFailure=yes \
      -o LogLevel=QUIET \
      -o PermitLocalCommand=yes \
      -o LocalCommand="echo connected" \
      -L "${local_port}:localhost:${remote_port}" \
      kevmoo.c.googlers.com
    echo "Tunnel disconnected (exit code $?). Retrying in 5 seconds..."
    sleep 5
    gcertstatus --check_remaining=1h --quiet || gcert
  done
}

