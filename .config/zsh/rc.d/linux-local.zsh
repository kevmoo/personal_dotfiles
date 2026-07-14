# ~/.zshrc.d/linux-local.zsh
# Portable Linux-specific configuration

# Linux-specific PATH additions
candidates+=(
  "$HOME/.local/bin"
  "$HOME/.local/share/dart/install/bin"
)

# ---------------------------------------------------------
# 1. Feature Detection (Cross-Platform & Secure)
# ---------------------------------------------------------

# Clipboard: Automatically handles Wayland (Home) vs X11 (Work)
if command -v wl-copy >/dev/null 2>&1; then
  alias pbcopy='wl-copy'
  alias pbpaste='wl-paste'
elif command -v xclip >/dev/null 2>&1; then
  alias pbcopy='xclip -sel clip'
  alias pbpaste='xclip -sel clip -o'
elif command -v xsel >/dev/null 2>&1; then
  alias pbcopy='xsel --clipboard --input'
  alias pbpaste='xsel --clipboard --output'
fi

# Chrome Executable: Generic paths for standard or flatpak installs
if [[ -f "/usr/bin/google-chrome" ]]; then
  export CHROME_EXECUTABLE="/usr/bin/google-chrome"
elif [[ -f "/var/lib/flatpak/exports/bin/com.google.Chrome" ]]; then
  export CHROME_EXECUTABLE="/var/lib/flatpak/exports/bin/com.google.Chrome"
elif [[ -f "$HOME/.local/share/flatpak/exports/bin/com.google.Chrome" ]]; then
  export CHROME_EXECUTABLE="$HOME/.local/share/flatpak/exports/bin/com.google.Chrome"
fi

# Editor: Fallback chain based on session type (SSH vs Local) and available tools
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
  # Connected via SSH: Always use a terminal-based editor
  if command -v vim >/dev/null 2>&1; then
    export EDITOR="vim"
  else
    export EDITOR="nano"
  fi
else
  # Local Session / CRD (Chrome Remote Desktop): Use GUI editor if available
  if command -v codium >/dev/null 2>&1; then
    export EDITOR="codium --wait"
  elif command -v code >/dev/null 2>&1; then
    export EDITOR="code --wait"
  else
    export EDITOR="vim"
  fi
fi

# ---------------------------------------------------------
# 2. SSH Agent Symlink Alignment
# ---------------------------------------------------------
# Maintain a static symlink to the active SSH agent socket.
# This allows background services (like Jetski) to access the agent
# even if their environment doesn't inherit the dynamic SSH_AUTH_SOCK.
if [[ -n "$SSH_AUTH_SOCK" && "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]]; then
  # Ensure the directory exists
  mkdir -p "$HOME/.ssh"
  # Update the symlink to point to the current active socket
  ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
fi

# Google Cloud SDK
if [[ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]]; then
  source "$HOME/google-cloud-sdk/path.zsh.inc"
fi
if [[ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]]; then
  source "$HOME/google-cloud-sdk/completion.zsh.inc"
fi


