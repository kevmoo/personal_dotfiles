. "$HOME/.cargo/env"

# Disable formatting/styling and paging for the AI agent (needs to be in .zshenv for non-interactive shell commands)
if [[ "$TERM" == "dumb" ]]; then
  export NO_COLOR=1
  export PAGER=cat
fi
