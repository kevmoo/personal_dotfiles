# Google Cloud SDK Path and Completion
if [[ -f "$HOME/.local/share/google-cloud-sdk/path.zsh.inc" ]]; then
  source "$HOME/.local/share/google-cloud-sdk/path.zsh.inc"
fi

if [[ -f "$HOME/.local/share/google-cloud-sdk/completion.zsh.inc" ]]; then
  source "$HOME/.local/share/google-cloud-sdk/completion.zsh.inc"
fi
