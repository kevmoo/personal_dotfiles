# Smart SSH Agent socket recovery
# If SSH_AUTH_SOCK is empty, or points to a non-existent/invalid socket file,
# try to recover by finding a living socket in ~/.ssh/agent/
if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! [[ -S "$SSH_AUTH_SOCK" ]]; then
  while IFS= read -r _sock_name; do
    [[ "$_sock_name" == s.* ]] || continue
    _sock="$HOME/.ssh/agent/$_sock_name"
    if SSH_AUTH_SOCK="$_sock" ssh-add -l >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
      mkdir -p "$HOME/.ssh"
      ln -sf "$_sock" "$HOME/.ssh/ssh_auth_sock"
      export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
      break
    fi
  done <<EOF
$(ls -1t "$HOME/.ssh/agent" 2>/dev/null)
EOF
  unset _sock_name _sock
fi

# Ensure tmux uses a safe, user-owned directory for sockets on Linux to avoid UID collisions in /tmp
if [[ "$OSTYPE" == linux* ]]; then
  export TMUX_TMPDIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
fi

if [[ -f "$HOME/.cargo/env" ]]; then
  . "$HOME/.cargo/env"
fi

if [[ "$OSTYPE" == darwin* ]]; then
  export ELAN_HOME="$HOME/.local/share/elan"
  if [[ -f "$ELAN_HOME/env" ]]; then
    . "$ELAN_HOME/env"
  fi
fi

# Ensure Dart install binaries, ~/.local/bin, mise shims, and depot_tools precede Homebrew/system PATH
# (placed after cargo/elan env so ~/.cargo/env does not prepend ahead of _user_path and defeat the prefix guard)
if [[ "$OSTYPE" == darwin* ]]; then
  _dart_install_bin="$HOME/Library/Application Support/Dart/install/bin"
else
  _dart_install_bin="$HOME/.local/state/Dart/install/bin"
fi
_user_path="$_dart_install_bin:$HOME/.local/bin:$HOME/.local/share/mise/shims"
if [[ -d "$HOME/github/depot_tools" ]]; then
  _user_path="$_user_path:$HOME/github/depot_tools"
fi
case "$PATH" in
  "$_user_path:"*) ;;
  *) export PATH="$_user_path:$PATH" ;;
esac
unset _user_path _dart_install_bin

export BASH_ENV="${BASH_ENV:-$HOME/.zshenv}"

# Dart SDK Siso build defaults (RBE enabled on macOS and corp Linux; offline Siso elsewhere)
export DART_SISO="${DART_SISO:-1}"
if [[ "$OSTYPE" == darwin* ]]; then
  export DART_RBE="${DART_RBE:-1}"
  export SISO_LIMITS="${SISO_LIMITS:-fastlocal=$(sysctl -n hw.logicalcpu)}"
elif [[ -d /google/src ]]; then
  export DART_RBE="${DART_RBE:-1}"
  export SISO_LIMITS="${SISO_LIMITS:-fastlocal=8}"
fi

# Disable formatting/styling, paging, and interactive prompts for non-interactive/agent shells
if [[ "${TERM:-}" == "dumb" || $- != *i* ]]; then
  export NO_COLOR=1
  export PAGER=cat
  export GIT_PAGER=cat
  export EDITOR=true
  export GIT_EDITOR=true
  export GIT_TERMINAL_PROMPT=0
fi
