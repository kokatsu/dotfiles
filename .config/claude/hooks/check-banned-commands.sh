#!/usr/bin/env bash
set -euo pipefail

RULES_FILE="$(dirname "${BASH_SOURCE[0]}")/banned-commands.json"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

while IFS= read -r rule; do
  pattern=$(echo "$rule" | jq -r '.pattern')
  message=$(echo "$rule" | jq -r '.message')
  if echo "$CMD" | grep -qE "$pattern"; then
    echo "$message" >&2
    exit 2
  fi
done < <(jq -c '.[]' "$RULES_FILE")
