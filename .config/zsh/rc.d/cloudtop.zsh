# ~/.config/zsh/rc.d/cloudtop.zsh
# Google Cloudtop / gLinux specific configuration

# ---------------------------------------------------------
# 1. Beads Configuration
# ---------------------------------------------------------
# Set the persistent identity for Beads audit trail on this machine
export BEADS_ACTOR="kevmoo@glinux-cloudtop"

# ---------------------------------------------------------
# 2. Prompt Configuration
# ---------------------------------------------------------
export PROMPT_PREFIX="☁️  "

# ---------------------------------------------------------
# 3. Security & Certificates
# ---------------------------------------------------------
if [[ -n "$SSH_CONNECTION" && -t 1 ]] && command -v gcertstatus >/dev/null; then
  gcertstatus --check_remaining=1h --quiet || gcert
fi

