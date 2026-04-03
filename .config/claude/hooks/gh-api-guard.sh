#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Only process gh api commands
if ! echo "$CMD" | grep -qE '(^|&&|;|\|\|?|\()\s*gh\s+api\b'; then
  exit 0
fi

# Check for state-changing HTTP methods
if echo "$CMD" | grep -qiE -- '-X\s*(POST|PUT|PATCH|DELETE)|--method\s+(POST|PUT|PATCH|DELETE)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "gh api: state-changing method detected"
    }
  }'
  exit 0
fi

# Default (GET): auto-allow
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "gh api: read-only (GET)"
  }
}'
