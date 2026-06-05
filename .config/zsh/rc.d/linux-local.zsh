# ~/.zshrc.d/linux-local.zsh
# Portable Linux-specific configuration

# Linux-specific PATH additions
candidates+=("$HOME/.local/bin")

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
if command -v flatpak >/dev/null 2>&1 && flatpak info com.vscodium.codium >/dev/null 2>&1; then
  alias codium='flatpak run com.vscodium.codium'
fi

if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
  # Connected via SSH: Always use a terminal-based editor
  if command -v vim >/dev/null 2>&1; then
    export EDITOR="vim"
  else
    export EDITOR="nano"
  fi
else
  # Local Session / CRD (Chrome Remote Desktop): Use GUI editor if available
  if command -v code >/dev/null 2>&1; then
    export EDITOR="code --wait"
  elif command -v flatpak >/dev/null 2>&1 && flatpak info com.vscodium.codium >/dev/null 2>&1; then
    export EDITOR="flatpak run com.vscodium.codium --wait"
  else
    export EDITOR="vim"
  fi
fi

# ---------------------------------------------------------
# 2. Environment Specifics (Immutable vs Standard)
# ---------------------------------------------------------

# NPM Wrapper to prevent global installs (only on ostree-based immutable systems like Bluefin)
if [[ -f /run/ostree-booted ]]; then
  eval '
    unalias npm 2>/dev/null
    function npm {
      if [[ "$*" == *"install -g"* ]] || [[ "$*" == *"--global"* ]]; then
        echo -e "\033[0;33m⚠️  Warning: You are trying to install a global NPM package.\033[0m"
        echo "Consider using npx, volta install, or adding to ~/.Brewfile."
        read -q "confirm?Do you still want to proceed? (y/N) "
        echo
        if [[ $confirm == [yY] ]]; then
          command npm "$@"
        fi
      else
        command npm "$@"
      fi
    }
  '
fi
