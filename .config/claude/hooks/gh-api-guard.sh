#!/usr/bin/env bash
# PreToolUse guard for `gh api`.
#
# Gated in settings.json by `if: "Bash(gh api *)"`, which fires on a per-subcommand
# prefix match (or when a command is too complex to parse). So this script only
# runs once a `gh api` invocation is already known to be present (or unparsable).
# It then auto-allows only when it can affirmatively prove the call is read-only;
# any uncertainty falls through to "ask" (fail-safe).
#
# Writes to gh's REST/GraphQL APIs can be triggered by:
#   - -X / --method overriding the verb to POST/PUT/PATCH/DELETE
#     (gh accepts -X POST, -XPOST, --method POST, --method=POST)
#   - --field / -F / --raw-field / -f          (typed + raw body fields → POST default)
#   - --input <file>                            (request body → POST default)
# When a parseable `gh api` subcommand sits alongside `eval`, `bash -c`, a
# subshell or backticks, the real verb may be hidden, so we defer to "ask".
# Note: `eval "gh api …"` (gh api buried inside eval's string arg) never trips
# the `if` gate, so this script won't see it — that form is blocked upstream by
# the banned-commands `eval` rule instead.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Defensive re-check that a `gh api` token is actually present. The `if` gate
# already guarantees this for parseable commands; this also covers the
# "too complex to parse" fallback, where the gate fires without a confirmed match.
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
