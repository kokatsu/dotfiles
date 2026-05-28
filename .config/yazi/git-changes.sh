#!/usr/bin/env bash
# `g j` picker (see keymap.toml): fuzzy-find a Git-changed file with fzf, preview
# its diff, and reveal it in Yazi at its real location.
#
# We read `git status --porcelain -z` rather than the newline form because git
# C-quotes any path with a space/tab/quote even under core.quotePath=false (e.g.
# `"with space.txt"`), which would then be passed verbatim to git/bat/cat and
# fail to resolve. The -z form emits raw, NUL-delimited paths. Renames arrive as
# two records (new path, then old path); the awk below drops the trailing old
# one, so every list line is just `XY <path>` and the new name wins.
set -u

# Self-invoked by fzf for each highlighted line: render that file's preview.
if [ "${1:-}" = "--preview" ]; then
  path=${2#???} # strip the "XY " status prefix
  if [ -d "$path" ]; then
    ls -A -- "$path"
  elif diff=$(git diff HEAD --color=always -- "$path" 2>/dev/null) && [ -n "$diff" ]; then
    printf '%s\n' "$diff" # tracked: combined staged + unstaged diff
  else
    bat --color=always --style=plain -- "$path" 2>/dev/null || cat -- "$path" # untracked
  fi
  exit 0
fi

self=$0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

sel=$(
  git -c core.quotePath=false status --porcelain -z |
    awk 'BEGIN { RS = "\0"; ORS = "\n" }
        skip { skip = 0; next }  # drop a renames old-path record
        { x = substr($0, 1, 1); y = substr($0, 2, 1)
          if (x == "R" || x == "C" || y == "R" || y == "C") skip = 1
          print }' |
    fzf --no-multi --layout=reverse --border --prompt="git changes> " \
      --preview "bash '$self' --preview {}"
) || exit 0
[ -n "$sel" ] || exit 0

ya emit reveal "$root/${sel#???}"
