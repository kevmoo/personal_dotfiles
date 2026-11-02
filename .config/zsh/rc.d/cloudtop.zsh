# ~/.config/zsh/rc.d/cloudtop.zsh
# Google Cloudtop / gLinux specific configuration

# ---------------------------------------------------------
# 1. Prompt Configuration
# ---------------------------------------------------------
export PROMPT_PREFIX="☁️  "

# ---------------------------------------------------------
# 2. Security & Certificates
# ---------------------------------------------------------
if [[ -n "$SSH_CONNECTION" && -t 1 ]] && command -v gcertstatus >/dev/null; then
  gcertstatus --check_remaining=1h --quiet || gcert
fi

# ---------------------------------------------------------
# 3. depot_tools Shared Git Cache
# ---------------------------------------------------------
export GIT_CACHE_PATH="$HOME/.cache/git_cache"

