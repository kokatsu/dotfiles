#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/files"

mode=${1:---worktree}
case "$mode" in
--staged)
  [[ $# -eq 1 ]]
  git diff --cached --name-only --diff-filter=ACMR -z >"$workdir/paths"
  ;;
--worktree)
  [[ $# -le 1 ]]
  git diff HEAD --name-only --diff-filter=ACMR -z >"$workdir/paths"
  git ls-files --others --exclude-standard -z >>"$workdir/paths"
  ;;
--base)
  [[ $# -eq 2 ]]
  if base=$(git rev-parse --verify --end-of-options "${2}^{commit}" 2>/dev/null) &&
    base=$(git merge-base "$base" HEAD); then
    git diff "$base" HEAD --name-only --diff-filter=ACMR -z >"$workdir/paths"
  else
    printf 'Comparison base unavailable; checking only the HEAD commit, not the full push range.\n' >&2
    if parent=$(git rev-parse --verify 'HEAD^' 2>/dev/null); then
      git diff "$parent" HEAD --name-only --diff-filter=ACMR -z >"$workdir/paths"
    else
      git ls-tree -r --name-only -z HEAD >"$workdir/paths"
    fi
  fi
  ;;
*)
  echo 'Usage: check-ai-writing.sh [--staged | --worktree | --base REF]' >&2
  exit 2
  ;;
esac

files=()
while IFS= read -r -d '' file; do
  case "$file" in
  *.md | *.markdown | *.html | *.htm) ;;
  *) continue ;;
  esac
  target="$workdir/files/$file"
  mkdir -p "${target%/*}"
  case "$mode" in
  --staged) git show ":$file" >"$target" ;;
  --base) git show "HEAD:$file" >"$target" ;;
  --worktree)
    [[ -f $file ]] || continue
    cp "$file" "$target"
    ;;
  esac
  files+=("$target")
done <"$workdir/paths"

[[ ${#files[@]} -gt 0 ]] || exit 0
status=0
textlint --config "$repo_root/.config/ai-writing/textlint-response.json" \
  --rulesdir "$repo_root/.config/ai-writing/rules" --no-color --format unix \
  -- "${files[@]}" >"$workdir/report" 2>&1 || status=$?
sed "s|$workdir/files/||g" "$workdir/report"
exit "$status"
