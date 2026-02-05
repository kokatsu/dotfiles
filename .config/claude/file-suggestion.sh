#!/usr/bin/env bash
set -euo pipefail

query=$(jq -r '.query // empty')

[[ -z "$query" ]] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"

# Common fd options
fd_opts=(
  --full-path
  --fixed-strings
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
)

# If query is an existing directory, list its contents
if [[ -d "$query" ]]; then
  fd --type f --type d --max-depth 1 --max-results 15 "${fd_opts[@]}" . "$query" 2>/dev/null || true
else
  # Sort by path depth (shallow first) so partial folder names surface the folder itself
  fd --type f --type d --max-results 200 "${fd_opts[@]}" "$query" 2>/dev/null | awk -F/ '{print NF, $0}' | sort -n | head -15 | cut -d' ' -f2- || true
fi
