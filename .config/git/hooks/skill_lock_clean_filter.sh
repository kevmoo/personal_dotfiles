#!/bin/bash
set -e

if ! command -v jq >/dev/null 2>&1; then
  cat
  exit 0
fi

# Pin updatedAt -> installedAt and strip trailing newline to match npx skills.
normalized=$(jq '.skills |= with_entries(
  if .value.installedAt then .value.updatedAt = .value.installedAt else . end
)')
printf '%s' "$normalized"
