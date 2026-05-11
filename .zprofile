# ~/.zprofile
# Sourced by login shells (both interactive and non-interactive)

# Ensure Homebrew is on the PATH (needed for mise on macOS if not already present)
if [[ -d "/opt/homebrew/bin" ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

# Initialize mise shims for non-interactive login shells (interactive login shells will use full activation in ~/.zshrc)
if [[ ! -o interactive ]] && command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh --shims)"
fi
