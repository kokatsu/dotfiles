#!/usr/bin/env bash
set -euo pipefail

query=$(jq -r '.query // empty')

[[ -z "$query" ]] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"

# Common fd options
fd_opts=(
  --full-path
  --hidden
  --exclude .git
  --exclude node_modules
  --exclude dist
  --exclude build
  --exclude .next
  --exclude coverage
  --exclude vendor
  --exclude __pycache__
  --exclude .cache
  --exclude target
  --color never
  --max-results 15
)

# If query is an existing directory, list its contents
if [[ -d "$query" ]]; then
  fd --type f --type d --max-depth 1 "${fd_opts[@]}" . "$query" 2>/dev/null || true
else
  fd --type f --type d "${fd_opts[@]}" "$query" 2>/dev/null || true
fi
