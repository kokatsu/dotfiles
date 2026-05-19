#!/usr/bin/env bash
# PreToolUse guard for `gh api`.
#
# Strategy (fail-safe): auto-allow only when we can affirmatively prove the
# invocation is read-only. Any uncertainty falls through to "ask".
#
# Writes to gh's REST/GraphQL APIs can be triggered by:
#   - -X / --method overriding the verb to POST/PUT/PATCH/DELETE
#     (gh accepts -X POST, -XPOST, --method POST, --method=POST)
#   - --field / -F / --raw-field / -f          (typed + raw body fields → POST default)
#   - --input <file>                            (request body → POST default)
# Wrappers like `eval`, `bash -c`, `xargs gh api`, $(…) substitutions or
# backticks hide the actual command from this regex pass, so we also
# defer those to "ask".

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Word-boundary match (not just substring) — anything mentioning `gh api`
# qualifies, including wrapped forms like `eval "gh api …"` which the
# shell-wrap check below catches.
if ! echo "$CMD" | grep -qE '\bgh\s+api\b'; then
  exit 0
fi

ask() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

allow() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Write indicators: explicit verb override OR body-bearing flags.
# -F/-f match both separated (`-F name=v`) and attached (`-Fname=v`) shorthand,
# both of which gh accepts and treats as POST.
write_re='(-X[= ]?(POST|PUT|PATCH|DELETE)\b|--method[= ]+(POST|PUT|PATCH|DELETE)\b|--field\b|--raw-field\b|--input\b|[[:space:]](-F|-f)([[:space:]]|[a-zA-Z_=]))'
if echo "$CMD" | grep -qiE -- "$write_re"; then
  ask "gh api: state-changing flag detected"
fi

# Indirect invocation hides the real command from this regex layer.
# Case-insensitive to also catch EVAL/BASH-style shouted variants.
shell_wrap_re='(\beval\b|\b(bash|sh)[[:space:]]+-c\b|\bxargs\b|`|\$\()'
if echo "$CMD" | grep -qiE -- "$shell_wrap_re"; then
  ask "gh api: indirect invocation (eval / sh -c / xargs / subshell) — confirm intent"
fi

# Plain `gh api …` with no write flags: GET (or read-only graphql query).
allow "gh api: read-only (GET)"
