# Smart SSH Agent socket recovery
# If SSH_AUTH_SOCK is empty, or points to a non-existent/invalid socket file,
# try to recover by finding a living socket in ~/.ssh/agent/
if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! [[ -S "$SSH_AUTH_SOCK" ]]; then
  for sock in $(ls -1dt "$HOME/.ssh/agent"/s.* 2>/dev/null); do
    if SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
      mkdir -p "$HOME/.ssh"
      ln -sf "$sock" "$HOME/.ssh/ssh_auth_sock"
      export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
      break
    fi
  done
fi

# Ensure tmux uses a safe, user-owned directory for sockets on Linux to avoid UID collisions in /tmp
if [[ "$(uname)" == "Linux" ]]; then
  export TMUX_TMPDIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
fi

if [[ -f "$HOME/.cargo/env" ]]; then
  . "$HOME/.cargo/env"
fi

if [[ "$(uname)" == "Darwin" ]]; then
  export ELAN_HOME="$HOME/.local/share/elan"
  if [[ -f "$ELAN_HOME/env" ]]; then
    . "$ELAN_HOME/env"
  fi
fi

# Ensure Dart install binaries, ~/.local/bin, and mise shims are always at the front of PATH
# (placed after cargo/elan env so ~/.cargo/env does not prepend ahead of _user_path and defeat the prefix guard)
_user_path="$HOME/.local/state/Dart/install/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims"
case "$PATH" in
  "$_user_path:"*) ;;
  *) export PATH="$_user_path:$PATH" ;;
esac
unset _user_path

# Disable formatting/styling and paging for the AI agent (needs to be in .zshenv for non-interactive shell commands)
if [[ "$TERM" == "dumb" ]]; then
  export NO_COLOR=1
  export PAGER=cat
fi

# Local checkout directory for kevmoo_scripts (`kscripts` binary staleness checks)
export KSCRIPTS_REPO_DIR="$HOME/github/kevmoo/scripts.dart"

