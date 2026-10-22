# ~/.zprofile
# Sourced by login shells (both interactive and non-interactive)

# Ensure Homebrew is on the PATH (needed for mise on macOS if not already present)
if [[ -d "/opt/homebrew/bin" ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

# Ensure Dart install binaries, ~/.local/bin, mise shims, and depot_tools precede Homebrew/system PATH
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
