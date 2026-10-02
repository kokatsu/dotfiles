#!/usr/bin/env bash
set -eEuo pipefail

# transcript-grep-guard.sh をラッパーごと PreToolUse の入力で叩き、Deno の起動、
# 権限指定、payload の読み取り、JSON の出力までが繋がっていることを allow と
# 無出力の 1 件ずつで確かめる。判定そのものは scripts/test-transcript-grep-guard.ts
# が固定する。

report_failure() {
  local rc=$? line=$1
  printf '%s:%s: exit %s: %s\n' "${BASH_SOURCE[0]##*/}" "$line" "$rc" "$BASH_COMMAND" >&2
}
trap 'report_failure "$LINENO"' ERR

repo_root=$(git rev-parse --show-toplevel)
guard="$repo_root/.config/claude/hooks/transcript-grep-guard.sh"

config_dir=$(mktemp -d)
trap 'rm -rf "$config_dir"' EXIT
mkdir -p "$config_dir/projects/-home-x"
transcript="$config_dir/projects/-home-x/s.jsonl"
printf '{}\n' >"$transcript"

run() {
  jq -Rn --arg c "$1" '{tool_input: {command: $c}}' |
    CLAUDE_CONFIG_DIR="$config_dir" bash "$guard"
}

out=$(run "grep -o -E '.{0,40}x' $transcript")
decision=$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")
if [[ $decision != allow ]]; then
  printf 'want allow, got: %s\n' "$out" >&2
  exit 1
fi

out=$(run "grep -o x /etc/passwd $transcript")
if [[ -n $out ]]; then
  printf 'want no output, got: %s\n' "$out" >&2
  exit 1
fi

echo "transcript-grep-guard: 2 passed"
