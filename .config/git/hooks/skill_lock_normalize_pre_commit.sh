#!/bin/bash
set -e

# Git normally executes pre-commit hooks from the root of the repository.
# However, this explicitly ensures the CWD is the repo root.
cd "$(git rev-parse --show-toplevel)"

# `npx skills` stamps every add/update with `updatedAt: <now>` and never reads
# it back. That makes it per-machine metadata in a shared file: two machines
# syncing the same upstream skill produce a one-line conflicting diff even when
# the vendored content is byte-identical. `installedAt` is preserved from the
# existing entry, so once committed it is stable everywhere. Pin updatedAt to it.
lock='.agents/.skill-lock.json'

# Only act when the lock is staged.
git diff --cached --name-only --diff-filter=ACM | grep -qx "$lock" || exit 0

# Safety check: refuse to normalize a partially staged lock, since re-adding it
# would silently stage the unstaged changes too.
if [ -n "$(git diff --name-only -- "$lock")" ]; then
  echo "❌ Error: $lock has both staged and unstaged changes."
  echo "Normalizing it would automatically stage your unstaged changes."
  echo "Stage or stash the remaining changes first."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Error: jq is required to normalize $lock (brew install jq)." >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# Command substitution strips the trailing newline, matching how `npx skills`
# writes the file, so the only diff is the updatedAt values themselves.
printf '%s' "$(jq '.skills |= with_entries(
  if .value.installedAt then .value.updatedAt = .value.installedAt else . end
)' "$lock")" > "$tmp"

if ! cmp -s "$tmp" "$lock"; then
  cat "$tmp" > "$lock"
  git add "$lock"
  echo "🔧 Normalized updatedAt -> installedAt in $lock"
fi
