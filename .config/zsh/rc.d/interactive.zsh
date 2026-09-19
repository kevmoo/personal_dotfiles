# ~/.zshrc.d/interactive.zsh - Zsh interactive features (Autosuggestions, Highlighting)

# 1. Path detection for plugins (Homebrew/Linuxbrew)
local plugin_paths=(
  "/opt/homebrew/share"       # Apple Silicon macOS
  "/usr/local/share"          # Intel macOS
  "/home/linuxbrew/.linuxbrew/share" # Linux
)

# 2. Source Plugins
for base in $plugin_paths; do
  if [[ -d "$base/zsh-syntax-highlighting" ]]; then
    source "$base/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  fi
  if [[ -d "$base/zsh-autosuggestions" ]]; then
    source "$base/zsh-autosuggestions/zsh-autosuggestions.zsh"
  fi
done

# 3. Configure Autosuggestions
# Use Ctrl-Space to accept the current suggestion (like Nushell)
bindkey '^ ' autosuggest-accept

# Highlight color (subtle gray)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'

# 4. Terminal Tab Title Configuration
# Helper to emit title escape sequences across iTerm2 (macOS) and Ptyxis/VTE/tmux (Linux):
# - iTerm2 combines OSC 1 (Tab/Icon title) and OSC 2 (Window title) into "Window - Tab"
#   (producing "~-~" when OSC 0 sets both to "%~"). Setting OSC 1 and clearing OSC 2 fixes this.
# - VTE-based terminals (Ptyxis on Bluefin, GNOME Terminal) ignore OSC 1 and require OSC 0/2.
function _emit_terminal_title() {
  local title="$1"
  if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    print -Pn "\e]1;${title}\a\e]2;\a"
  else
    print -Pn "\e]0;${title}\a"
  fi
}

# Idle prompt title: show current directory (e.g. "~" or "~/github/web")
function set_terminal_title() {
  _emit_terminal_title "%~"
}

# Running command title: show "<cmd>: <dir>" (e.g. "jetski: ~") while a foreground job runs
function set_terminal_title_preexec() {
  # Extract the first command word (ignoring leading VAR=val assignments)
  local -a words=(${(z)1})
  local cmd="${words[1]}"
  while [[ "$cmd" == *=* && ${#words} -gt 1 ]]; do
    shift words
    cmd="${words[1]}"
  done
  # Escape any '%' in command name so print -Pn doesn't treat it as a prompt expansion
  cmd="${cmd//\%/%%}"
  _emit_terminal_title "${cmd}: %~"
}

# Safely register the title functions to Zsh hooks
autoload -Uz add-zsh-hook
add-zsh-hook chpwd set_terminal_title
add-zsh-hook precmd set_terminal_title
add-zsh-hook preexec set_terminal_title_preexec


