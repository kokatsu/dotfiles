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

# If query is an existing directory, list its contents (directories first)
if [[ -d "$query" ]]; then
  {
    fd --type d --max-depth 1 --max-results 15 "${fd_opts[@]}" . "$query" 2>/dev/null || true
    fd --type f --max-depth 1 --max-results 15 "${fd_opts[@]}" . "$query" 2>/dev/null || true
  } | head -15
elif [[ "$query" == */* ]] && [[ -d "$(dirname "$query")" ]]; then
  # Partial path with existing parent (e.g. ../dotfiles/.con, src/comp)
  fd --type f --type d --max-results 200 "${fd_opts[@]}" "$(basename "$query")" "$(dirname "$query")" 2>/dev/null |
    awk -F/ '{print NF, $0}' | sort -sn | head -15 | cut -d' ' -f2- || true
else
  # Sort by path depth (shallow first) so partial folder names surface the folder itself
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    git ls-files --cached --others --exclude-standard 2>/dev/null |
      grep -F "$query" |
      awk -F/ '{print NF, $0}' | sort -sn | head -15 | cut -d' ' -f2- || true
  else
    fd --type f --type d --max-results 200 --strip-cwd-prefix "${fd_opts[@]}" "$query" 2>/dev/null |
      awk -F/ '{print NF, $0}' | sort -sn | head -15 | cut -d' ' -f2- || true
  fi
fi
