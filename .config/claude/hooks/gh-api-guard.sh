#!/usr/bin/env bash
# Launcher for gh-api-guard.ts.
#
# It exists so settings.json names one command per hook and so the Deno
# permission set can be built from paths this script resolves.
#
# Every failure here ends in "ask", never a block. `gh api *` is not
# allowlisted, so an ask is exactly where the command would land without this
# hook: it can only remove a prompt, never add one. That is the opposite of
# check-banned-commands.sh, whose every failure must exit 2.
set -uo pipefail

# The reasons below are fixed ASCII with no quote or backslash, so they need no
# JSON escaping.
ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"gh api: %s"}}\n' "$1"
  exit 0
}

# A terminal on stdin means this was not invoked by Claude Code; reading it
# would hang.
[[ -t 0 ]] && ask "stdin is a terminal, not a piped payload"

HOOKS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" ||
  ask "cannot resolve the hooks directory"
script="$HOOKS_DIR/gh-api-guard.ts"
[[ -r $script ]] || ask "cannot read $script"

shfmt_bin="$(command -v shfmt)" || ask "shfmt not found"
command -v deno >/dev/null 2>&1 || ask "deno not found"

# exec: a Deno failure prints nothing on stdout, and Claude Code falls back to
# the normal prompt, which is the same ask this script would emit.
exec deno run \
  --no-prompt \
  --allow-run="$shfmt_bin" \
  "$script" "$shfmt_bin"
