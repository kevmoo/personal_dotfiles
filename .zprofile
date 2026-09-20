# ~/.zprofile
# Sourced by login shells (both interactive and non-interactive)

# Ensure Homebrew is on the PATH (needed for mise on macOS if not already present)
if [[ -d "/opt/homebrew/bin" ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

# Ensure Dart install binaries, ~/.local/bin, and mise shims take precedence over Homebrew/system PATH
export PATH="$HOME/.local/state/Dart/install/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
