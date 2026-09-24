#!/usr/bin/env bash
set -euo pipefail

# .config/claude/hooks/check-managed-paths.sh を PreToolUse の入力で叩き、
# 「正規化した先が /nix/store の配下なら exit 2」を固定する。readlink -f は
# 最後の要素が存在しなくても正規化するので、実在するストアパスは要らない。

repo_root=$(git rev-parse --show-toplevel)
hook="$repo_root/.config/claude/hooks/check-managed-paths.sh"
fail=0

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
ln -s /nix/store/zzzz-nonexistent "$test_dir/storelink"
ln -s /nix/store "$test_dir/storedir"
ln -s "$hook" "$test_dir/repolink"
touch "$test_dir/plain"

check() {
  local want=$1 label=$2 payload=$3 rc=0
  printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1 || rc=$?
  if [[ $rc == "$want" ]]; then
    printf '  PASS exit %s: %s\n' "$rc" "$label"
  else
    printf '  FAIL want %s got %s: %s\n' "$want" "$rc" "$label" >&2
    fail=1
  fi
}

check_path() {
  check "$1" "$2" "$(jq -n --arg f "$2" '{tool_input: {file_path: $f}}')"
}

# Home Manager がストアへ張ったリンク
check_path 2 "$test_dir/storelink"
check_path 2 "$test_dir/storedir/new.txt"

# mkOutOfStoreSymlink はリポジトリへ解決されるので通す
check_path 0 "$test_dir/repolink"
check_path 0 "$test_dir/plain"
check_path 0 "$test_dir/nodir/new.txt"
check 0 'no file_path' '{"tool_input":{"notebook_path":"x"}}'

if [[ $fail -ne 0 ]]; then
  exit 1
fi
printf 'check-managed-paths hook tests passed\n'
