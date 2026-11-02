#!/usr/bin/env bash
# `g j` picker (see nix/home/programs/yazi.nix): fuzzy-find a Git-changed file with fzf, preview
# its diff, and reveal it in Yazi at its real location.
#
# We read `git status --porcelain -z` rather than the newline form because git
# C-quotes any path with a space/tab/quote even under core.quotePath=false (e.g.
# `"with space.txt"`), which would then be passed verbatim to git/bat/cat and
# fail to resolve. The -z form emits raw, NUL-delimited paths. Renames arrive as
# two records (new path, then old path); list_changes drops the trailing old
# one, so every list line is just `XY <path>` and the new name wins. The loop
# reads NUL with bash because macOS awk cannot split records on NUL.
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

list_changes() {
  local rec skip=0
  while IFS= read -r -d '' rec; do
    if ((skip)); then
      skip=0
      continue
    fi
    case ${rec:0:2} in
    R? | C? | ?R | ?C) skip=1 ;;
    esac
    printf '%s\n' "$rec"
  done < <(git -c core.quotePath=false status --porcelain -z)
}

self=$0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

sel=$(
  list_changes |
    fzf --no-multi --layout=reverse --border --prompt="git changes> " \
      --preview "bash '$self' --preview {}"
) || exit 0
[ -n "$sel" ] || exit 0

ya emit reveal "$root/${sel#???}"
