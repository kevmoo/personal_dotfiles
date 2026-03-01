# ~/.zshrc.d/shell-power.zsh

# Fuzzy Finder (History, File search)
if (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi

# Smart CD
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# Modern replacements
if (( $+commands[eza] )); then
  alias ls='eza --icons --git'
fi
if (( $+commands[bat] )); then
  alias cat='bat'
fi
