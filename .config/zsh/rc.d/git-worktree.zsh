# Git Worktree Helpers
#
# 1. `gworktree-new <work-description>`
#    Creates a new Git worktree in a sibling directory named `../_<repo_name>-<work-description>`
#    on a new branch named `<work-description>` and automatically `cd`s into it.
#
# 2. `gworktree-prune`
#    Prunes stale worktrees (with formatted output) and lists active worktrees.

gworktree-new() {
  if [[ -z "$1" || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: gworktree-new <work-description>"
    echo ""
    echo "Creates a new git worktree in a sibling directory:"
    echo "  ../_<repo_name>-<work-description>"
    echo "on a new branch named <work-description>, and automatically changes directory (cd) into it."
    if [[ -z "$1" ]]; then
      return 1
    else
      return 0
    fi
  fi

  local repo_root repo_name target_dir
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ $? -ne 0 || -z "$repo_root" ]]; then
    echo "Error: Not inside a git repository."
    return 1
  fi

  repo_name=$(basename "$repo_root")
  target_dir="../_${repo_name}-$1"

  echo "Creating worktree at '${target_dir}' on branch '$1'..."
  if git worktree add -b "$1" "$target_dir"; then
    cd "$target_dir"
  fi
}

gworktree-prune() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: gworktree-prune"
    echo ""
    echo "Prunes stale worktrees and lists active worktrees."
    return 0
  fi

  local prune_output
  prune_output=$(git worktree prune --verbose 2>&1)
  if [[ -z "$prune_output" ]]; then
    echo "✅ Nothing to prune"
  else
    echo "$prune_output"
  fi

  git worktree list
}
