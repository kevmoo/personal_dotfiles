# ~/.config/zsh/rc.d/bluefin.zsh
# Bluefin-DX / rpm-ostree immutable Linux specific configuration

# ---------------------------------------------------------
# 1. NPM Wrapper (Immutable Safeguards)
# ---------------------------------------------------------
# Prevent global NPM installs on immutable host systems
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
