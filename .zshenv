# Smart SSH Agent socket recovery
# If SSH_AUTH_SOCK is empty, or points to a non-existent/invalid socket file,
# try to recover by finding a living socket in ~/.ssh/agent/
if [[ -z "$SSH_AUTH_SOCK" ]] || ! [[ -S "$SSH_AUTH_SOCK" ]]; then
  for sock in $(ls -t ~/.ssh/agent/s.* 2>/dev/null); do
    if SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
      mkdir -p ~/.ssh
      ln -sf "$sock" ~/.ssh/ssh_auth_sock
      export SSH_AUTH_SOCK=~/.ssh/ssh_auth_sock
      break
    fi
  done
fi

if [[ -f "$HOME/.cargo/env" ]]; then
  . "$HOME/.cargo/env"
fi

# Disable formatting/styling and paging for the AI agent (needs to be in .zshenv for non-interactive shell commands)
if [[ "$TERM" == "dumb" ]]; then
  export NO_COLOR=1
  export PAGER=cat
fi

