# ~/.zshrc.d/linux-local.zsh

# Linux-specific PATH additions
# candidates+=("$HOME/some/linux/only/path")

export CHROME_EXECUTABLE="/var/lib/flatpak/exports/bin/com.google.Chrome"

# Linux needs aliases for pbcopy/pbpaste (already native on macOS)
alias pbcopy='wl-copy'
alias pbpaste='wl-paste'

# Use VSCodium (Flatpak) as the editor
alias codium='flatpak run com.vscodium.codium'
export EDITOR="codium --wait"

# NPM Wrapper to prevent global installs on Bluefin/Silverblue
# We use eval to prevent the Zsh parser from expanding the 'npm' alias on Mac
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
