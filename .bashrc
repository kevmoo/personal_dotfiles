# .bashrc

npm() {
  if [[ "$*" == *"install -g"* ]] || [[ "$*" == *"--global"* ]]; then
    echo -e "\033[0;33m⚠️  Warning: You are trying to install a global NPM package.\033[0m"
    echo "On Bluefin-DX, consider using 'npx' or adding it to your ~/.Brewfile if available."
    echo "Or `volta install`"
    read -p "Do you still want to proceed? (y/N) " confirm
    if [[ $confirm == [yY] ]]; then
      command npm "$@"
    fi
  else
    command npm "$@"
  fi
}

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

export VOLTA_HOME="$HOME/.volta"

# User specific environment
for dir in "$HOME/.local/bin" "$HOME/bin" "$HOME/github/flutter/bin" "$HOME/.pub-cache/bin" "$VOLTA_HOME/bin"; do
    if [[ -d "$dir" && ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
    fi
done
export PATH
export CHROME_EXECUTABLE="/var/lib/flatpak/exports/bin/com.google.Chrome"

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
alias ..='cd ..'
alias ...='cd ../..'
alias a='ls -la'
alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
alias pbcopy='wl-copy'
alias pbpaste='wl-paste'
alias pu='dart pub upgrade'

if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

brewall() {
    echo "Running: brew update"
    brew update
    echo "Running: brew bundle --upgrade --global --cleanup"
    brew bundle --upgrade --global --cleanup
}
