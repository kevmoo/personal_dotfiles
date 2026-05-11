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
