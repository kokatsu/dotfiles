#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
guard="$repo_root/.config/claude/hooks/herdr-peer-command-guard.sh"

expect_blocked() {
  local command_text=$1 status

  set +e
  jq -cn --arg command "$command_text" '{tool_input: {command: $command}}' | bash "$guard" >/dev/null 2>&1
  status=$?
  set -e

  if [[ $status -ne 2 ]]; then
    printf 'expected guard to block (%s), got status %s\n' "$command_text" "$status" >&2
    return 1
  fi
}

expect_allowed() {
  local command_text=$1

  if ! jq -cn --arg command "$command_text" '{tool_input: {command: $command}}' | bash "$guard" >/dev/null 2>&1; then
    printf 'expected guard to allow: %s\n' "$command_text" >&2
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
)

allowed_commands=(
  'herdr agent list'
  'herdr agent read w1:p1'
  'herdr-peer prompt "review the diff"'
  'git commit -m "mention herdr agent prompt in documentation"'
  "printf '%s\\n' 'herdr pane send-text w1:p1 test'"
)

for command_text in "${blocked_commands[@]}"; do
  expect_blocked "$command_text"
done

for command_text in "${allowed_commands[@]}"; do
  expect_allowed "$command_text"
done
