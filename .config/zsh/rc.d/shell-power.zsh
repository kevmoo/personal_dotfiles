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
  # Synchronize LS_COLORS and EZA_COLORS for consistent cyan directories (di=01;36)
  # This ensures both the completion menu and ls output are legible.
  export LS_COLORS="${LS_COLORS/di=01;34/di=01;36}"
  # di=directory, ln=symlink, ex=executable, da=date, uu=user, gu=group, sn=size
  # Using 36 (Cyan) for directories and dates to avoid the "too dark" blue.
  export EZA_COLORS="di=1;36:ln=35:ex=31:da=36:uu=33:gu=33:sn=32:so=32:pi=33:bd=34;46:cd=34;43:su=0;41:sg=0;46:tw=0;42:ow=0;43"
  if [[ "$TERM" == "dumb" ]]; then
    alias ls='eza --icons --git'
  else
    alias ls='eza --icons --git --color=always'
  fi
fi
if (( $+commands[bat] )) && [[ "$TERM" != "dumb" ]]; then
  alias cat='bat --color=always'
fi
