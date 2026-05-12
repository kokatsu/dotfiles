#!/usr/bin/env bash
set -euo pipefail

query=$(jq -r '.query // empty')

[[ -z "$query" ]] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"

# Common fd options. --full-path is added per-branch — branch 2 (`<dir>/<query>`)
# must NOT use --full-path because fd resolves the search root to its absolute
# path before matching, so e.g. `me` in `.kokatsu` would match the leading
# `/home/...` prefix and surface unrelated entries.
fd_opts=(
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

# If query is an existing directory, list its contents (directories first).
# Empty pattern lists every entry under the search path regardless of name.
if [[ -d "$query" ]]; then
  {
    fd --type d --no-ignore-vcs --max-depth 1 --max-results 15 "${fd_opts[@]}" '' "$query" 2>/dev/null || true
    fd --type f --no-ignore-vcs --max-depth 1 --max-results 15 "${fd_opts[@]}" '' "$query" 2>/dev/null || true
  } | head -15
elif [[ "$query" == */* ]] && [[ -d "$(dirname "$query")" ]]; then
  # Partial path with existing parent (e.g. ../dotfiles/.con, src/comp).
  # Rank: prefix match on relative path > substring; then dir > file; then shallow > deep.
  base=$(basename "$query")
  dir=$(dirname "$query")
  {
    fd --type d --no-ignore-vcs "${fd_opts[@]}" "$base" "$dir" 2>/dev/null |
      awk -v q="$query" -F/ '{p=(index($0,q)==1)?0:1; printf "%d\t0\t%d\t%s\n", p, NF, $0}'
    fd --type f --no-ignore-vcs "${fd_opts[@]}" "$base" "$dir" 2>/dev/null |
      awk -v q="$query" -F/ '{p=(index($0,q)==1)?0:1; printf "%d\t1\t%d\t%s\n", p, NF, $0}'
  } | sort -t$'\t' -k1,1n -k2,2n -k3,3n | head -15 | cut -f4- || true
else
  # Rank: prefix match on relative path > substring; then dir > file; then shallow > deep.
  # --no-ignore-vcs lets gitignored entries (e.g. .local/) surface; --exclude in fd_opts still suppresses noisy dirs.
  # --full-path matches the query against the full relative path so e.g. `src/comp` still works when branch 2 misses.
  {
    fd --type d --no-ignore-vcs --full-path --strip-cwd-prefix "${fd_opts[@]}" "$query" 2>/dev/null |
      awk -v q="$query" -F/ '{p=(index($0,q)==1)?0:1; printf "%d\t0\t%d\t%s\n", p, NF, $0}'
    fd --type f --no-ignore-vcs --full-path --strip-cwd-prefix "${fd_opts[@]}" "$query" 2>/dev/null |
      awk -v q="$query" -F/ '{p=(index($0,q)==1)?0:1; printf "%d\t1\t%d\t%s\n", p, NF, $0}'
  } | sort -t$'\t' -k1,1n -k2,2n -k3,3n | head -15 | cut -f4- || true
fi
