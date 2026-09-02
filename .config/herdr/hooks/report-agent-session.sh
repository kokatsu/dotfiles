#!/usr/bin/env bash
# Launcher for report-agent-session.ts, shared by the Claude Code and Codex
# SessionStart hooks.
#
# Usage: report-agent-session.sh session <claude|codex>
#
# The action word is the guard the hooks this replaces already had, and the
# agent picks which profile the script reports under; both are matched against
# fixed lists so a hook definition cannot name anything else.
#
# It exists so neither settings.json nor hooks.json repeats the permission set,
# and so --allow-run can be built from $HERDR_BIN_PATH, which Deno's static
# flags cannot expand themselves. Anything that stops the hook from running --
# no Herdr, no Deno, no script -- exits 0 without reporting: unlike the cache
# token, an agent session has no "clear" call to fall back on.

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$here/report-agent-session.ts"

case "${1:-}" in
session) ;;
*) exit 0 ;;
esac

agent="${2:-}"
case "$agent" in
claude | codex) ;;
*) exit 0 ;;
esac

[[ ${HERDR_ENV:-} == 1 ]] || exit 0
[[ -n ${HERDR_PANE_ID:-} ]] || exit 0
[[ -n ${HERDR_SOCKET_PATH:-} ]] || exit 0

# Herdr passes its own absolute store path. Preferring it over the bare name
# keeps the hook working while a home-manager switch is swapping the profile,
# and grants one fewer permission than allowing both.
herdr_bin="$(command -v "${HERDR_BIN_PATH:-herdr}" 2>/dev/null || true)"
if [[ -z $herdr_bin ]]; then
  exit 0
fi

if ! command -v deno >/dev/null 2>&1 || [[ ! -r $script ]]; then
  exit 0
fi

deno run \
  --no-prompt \
  --allow-env=HERDR_ENV,HERDR_PANE_ID,HERDR_SOCKET_PATH \
  --allow-run="$herdr_bin" \
  "$script" "$agent" "$herdr_bin"

exit 0
