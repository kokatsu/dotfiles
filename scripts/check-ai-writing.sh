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
  git diff --cached --name-only --diff-filter=ACMRT -z >"$workdir/paths"
  ;;
--worktree)
  [[ $# -le 1 ]]
  git diff HEAD --name-only --diff-filter=ACMRT -z >"$workdir/paths"
  git ls-files --others --exclude-standard -z >>"$workdir/paths"
  ;;
--base | --push-base)
  [[ $# -eq 2 ]]
  if [[ $mode == --push-base && ! $2 =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
    printf 'Invalid previous push SHA: %s\n' "$2" >&2
    exit 1
  fi
  if [[ -n $2 ]] && base=$(git rev-parse --verify --end-of-options "${2}^{commit}" 2>/dev/null); then
    if [[ $mode == --base ]] && ! git merge-base --is-ancestor "$base" HEAD; then
      printf 'Comparison base is not an ancestor of HEAD: %s\n' "$base" >&2
      exit 1
    fi
    git diff "$base" HEAD --name-only --diff-filter=ACMRT -z >"$workdir/paths"
  elif [[ $mode == --push-base ]]; then
    printf 'Previous push SHA unavailable; checking all documents in HEAD: %s\n' "$2" >&2
    git ls-tree -r --name-only -z HEAD >"$workdir/paths"
  else
    printf 'Cannot resolve comparison base: %s\n' "$2" >&2
    exit 1
  fi
  ;;
*)
  echo 'Usage: check-ai-writing.sh [--staged | --worktree | --base REF | --push-base SHA]' >&2
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
  --staged)
    file_mode=$(git --literal-pathspecs ls-files --format='%(objectmode)' -- "$file")
    [[ $file_mode == 100??? ]] || continue
    git show ":$file" >"$target"
    ;;
  --base | --push-base)
    file_mode=$(git --literal-pathspecs ls-tree --format='%(objectmode)' HEAD -- "$file")
    [[ $file_mode == 100??? ]] || continue
    git show "HEAD:$file" >"$target"
    ;;
  --worktree)
    [[ -f $file && ! -L $file ]] || continue
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
