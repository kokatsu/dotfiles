#!/usr/bin/env bash
set -euo pipefail

# settings.json の Edit/Write 用フック (agent-guard managed-paths) を
# PreToolUse の入力で叩き、「正規化した先が /nix/store の配下なら exit 2」と、
# 判定に届かない失敗も exit 2 になることを固定する。最後の要素は存在しなくても
# 正規化するので、実在するストアパスは要らない。正規化の細部は go test が見る。

repo_root=$(git rev-parse --show-toplevel)
fail=0

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
(cd "$repo_root/tools/agent-guard" && go build -o "$test_dir/bin/agent-guard" .)
ln -s /nix/store/zzzz-nonexistent "$test_dir/storelink"
ln -s /nix/store "$test_dir/storedir"
touch "$test_dir/plain"
ln -s "$test_dir/plain" "$test_dir/repolink"

hook_command=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Edit|Write") | .hooks[0].command' \
  "$repo_root/.config/claude/settings.json")
hook_path="$test_dir/bin:$PATH"

check() {
  local want=$1 label=$2 payload=$3 rc=0
  printf '%s' "$payload" | PATH="$hook_path" /bin/sh -c "$hook_command" >/dev/null 2>&1 || rc=$?
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

# 判定に届かない失敗も、exit 2 でなければ Claude Code は編集を通す。
check 2 'malformed payload' '{'
check 2 'non-string file_path' '{"tool_input":{"file_path":42}}'
hook_path=/usr/bin:/bin
check 2 'binary not found' "$(jq -n --arg f "$test_dir/storelink" '{tool_input: {file_path: $f}}')"

if [[ $fail -ne 0 ]]; then
  exit 1
fi
printf 'check-managed-paths hook tests passed\n'
