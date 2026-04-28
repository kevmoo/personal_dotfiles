#!/bin/bash
set -e

# Git normally executes pre-commit hooks from the root of the repository.
# However, this explicitly ensures the CWD is the repo root.
cd "$(git rev-parse --show-toplevel)"

# Find all staged Dart files (Added, Copied, Modified)
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.dart$' || true)

if [ -z "$staged_files" ]; then
  exit 0
fi

# Safety check: Prevent staging unstaged changes in partially staged files
# If a staged file also has unstaged changes, formatting and adding it
# would accidentally stage the unstaged changes.
has_unstaged=$(git diff --name-only $staged_files || true)
if [ -n "$has_unstaged" ]; then
  echo "❌ Error: Cannot safely format partially staged Dart files."
  echo "The following files have both staged and unstaged changes:"
  echo "$has_unstaged"
  echo ""
  echo "Formatting them would automatically stage your unstaged changes."
  echo "Please fully stage or stash your changes before committing."
  exit 1
fi

echo "✨ Formatting staged Dart files..."
dart format $staged_files

# Add the formatted files back to the index
git add $staged_files

# Fail if formatting the dirty Dart file yields a blank commit
if [ -z "$(git diff --cached --name-only)" ]; then
  echo "❌ Error: Formatting reverted all staged changes, resulting in an empty commit."
  exit 1
fi
