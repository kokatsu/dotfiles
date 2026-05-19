#!/usr/bin/env bash
set -euo pipefail

RULES_FILE="$(dirname "${BASH_SOURCE[0]}")/banned-commands.json"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Parse the full ruleset in two jq passes so the per-rule match loop can run
# entirely in-shell. With ~13 rules this avoids ~26 jq subprocess forks per
# Bash tool call (this hook runs on every Claude Bash invocation).
# while-read instead of mapfile to stay compatible with stock macOS Bash 3.2.
patterns=()
messages=()
while IFS= read -r line; do patterns+=("$line"); done < <(jq -r '.[].pattern' "$RULES_FILE")
while IFS= read -r line; do messages+=("$line"); done < <(jq -r '.[].message' "$RULES_FILE")

for i in "${!patterns[@]}"; do
  if [[ $CMD =~ ${patterns[i]} ]]; then
    printf '%s\n' "${messages[i]}" >&2
    exit 2
  fi
done
