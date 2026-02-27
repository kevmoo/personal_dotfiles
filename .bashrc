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

# User specific environment
for dir in "$HOME/.local/bin" "$HOME/bin" "$HOME/github/flutter/bin"; do
    if [[ ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
    fi
done
export PATH
export CHROME_EXECUTABLE="/var/lib/flatpak/exports/bin/com.google.Chrome"

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
alias a='ls -la'
alias pu='dart pub upgrade'
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc
alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
