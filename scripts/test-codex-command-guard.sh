#!/usr/bin/env bash
set -euo pipefail

# Codex が登録する `agent-guard codex` の入口を検証する。判定そのものは
# tools/agent-guard の go test が、Claude Code 側の `banned` の入口は
# scripts/test-banned-commands.sh が見る。
repo_root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
guard="$work/agent-guard"
(cd "$repo_root/tools/agent-guard" && go build -o "$guard" .)

guard_status() {
  local status
  set +e
  printf '%s' "$1" | "$guard" codex >/dev/null 2>&1
  status=$?
  set -e
  printf '%s' "$status"
}

bash_payload() {
  jq -cn --arg command "$1" '{tool_name: "Bash", tool_input: {command: $command}}'
}

expect_status() {
  local want=$1 label=$2 payload=$3 got
  got=$(guard_status "$payload")
  if [[ $got != "$want" ]]; then
    printf 'expected status %s (%s), got %s\n' "$want" "$label" "$got" >&2
    return 1
  fi
}

blocked_commands=(
  'herdr agent prompt w1:p1 test'
  'exec herdr agent prompt w1:p1 test'
  'if true; then herdr agent prompt w1:p1 test; fi'
  '/usr/bin/env herdr agent prompt w1:p1 test'
  'exec /usr/bin/env -i FOO=bar herdr pane send-text w1:p1 test'
  'case x in x) herdr agent send-keys w1:p1 test ;; esac'
  'while herdr pane run w1:p1 test; do true; done'
  $'true\nherdr pane send-keys w1:p1 test'
  'rm -rf build'
  'git reset --hard HEAD~1'
  'git push --force origin main'
  'grep -r foo . && rm x'
  'echo "unterminated'
  'gh api repos/o/r'
  'doas gh api repos/o/r'
)

allowed_commands=(
  'herdr agent list'
  'herdr agent read w1:p1'
  'herdr-peer prompt "review the diff"'
  'git commit -m "mention herdr agent prompt in documentation"'
  "printf '%s\\n' 'herdr pane send-text w1:p1 test'"
  'grep -r foo .'
  'gomi build'
  'gh api -X GET repos/o/r'
  'echo "run gh api later"'
)

for command_text in "${blocked_commands[@]}"; do
  expect_status 2 "$command_text" "$(bash_payload "$command_text")"
done

for command_text in "${allowed_commands[@]}"; do
  expect_status 0 "$command_text" "$(bash_payload "$command_text")"
done

# Bash 以外は素通しし、Bash なのにコマンドを読めない入力と tool_name のない
# 入力は判定に届かないのでブロックする。
expect_status 0 'non-Bash tool' '{"tool_name":"apply_patch","tool_input":{"command":"rm -rf build"}}'
expect_status 2 'Bash without command' '{"tool_name":"Bash","tool_input":{}}'
expect_status 2 'Bash with null command' '{"tool_name":"Bash","tool_input":{"command":null}}'
expect_status 2 'Bash with non-string command' '{"tool_name":"Bash","tool_input":{"command":42}}'
expect_status 2 'missing tool_name' '{"tool_input":{"command":"ls"}}'
expect_status 2 'non-string tool_name' '{"tool_name":42,"tool_input":{"command":"ls"}}'
expect_status 2 'malformed payload' '{'
