#!/usr/bin/env bash
# Require Codex to make the HTTP method explicit for every `gh api` call.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
GH_API_RE='(^|[;&|()[:space:]])gh[[:space:]]+api([;&|()[:space:]]|$)'
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
