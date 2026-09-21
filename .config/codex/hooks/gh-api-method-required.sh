#!/usr/bin/env bash
# Require Codex to make the HTTP method explicit for every `gh api` call.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
# 空白を境界にすると `echo "run gh api later"` のような地の文まで拒否するので、
# 行頭か制御演算子のあとだけを命令の開始とみなす。ラッパー以降の語は全て読み飛ばす
# ので、`sudo echo "gh api"` のようなものは拒否側に倒れる。
WRAPPER_RE='(([^;&|(){}[:space:]]*/)?(env|command|exec|sudo|nohup|nice|time|timeout|builtin)[[:space:]]+([^;&|(){}[:space:]]+[[:space:]]+)*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
GH_API_RE="(^|[;&|(){}])[[:space:]]*${WRAPPER_RE}([^;&|(){}[:space:]]*/)?gh[[:space:]]+api([;&|(){}[:space:]]|\$)"
METHOD_RE='(^|[[:space:]])(-[[:alnum:]]*X([[:space:]=]+[A-Za-z]+|[A-Za-z]+)|--method[[:space:]=]+[A-Za-z]+)'

GH_API_COUNT=$(printf '%s\n' "$COMMAND" | grep -oE "$GH_API_RE" | grep -c . || true)

if [ "$GH_API_COUNT" -eq 0 ]; then
  exit 0
fi

deny() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Keep the check fail-closed: one hook invocation must correspond to one
# inspectable `gh api` call, rather than letting a method on one call satisfy
# another call in the same compound shell command.
if [ "$GH_API_COUNT" -gt 1 ]; then
  deny "gh api: run each invocation as a separate command and specify -X or --method"
fi

if ! printf '%s\n' "$COMMAND" | grep -qE -- "$METHOD_RE"; then
  deny "gh api: an explicit HTTP method is required; use -X GET or --method GET"
fi
