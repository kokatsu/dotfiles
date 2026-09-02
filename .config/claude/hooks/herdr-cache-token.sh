#!/usr/bin/env bash
# Launcher for herdr-cache-token.ts.
#
# It exists so settings.json names one command per hook instead of repeating the
# permission set three times, and so the allow-lists can be built from $HOME and
# $HERDR_BIN_PATH, which Deno's static flags cannot expand themselves.
#
# Permissions are the narrowest that still let the hook read transcripts, keep its
# cursor, and reach the Herdr socket. Anything that stops the hook from running --
# no Deno, no script, a Deno that will not start -- clears the token rather than
# leaving one standing that nothing is maintaining, and always exits 0 so a
# display-only hook never fails the turn.

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state="$HOME/.local/state/herdr-cache-token"
script="$here/herdr-cache-token.ts"

# Herdr passes its own absolute store path. Preferring it over the bare name keeps
# the hook working while a home-manager switch is swapping the profile, and grants
# one fewer permission than allowing both. Resolving it here also lets the fallback
# below run it without a PATH.
herdr_bin="$(command -v "${HERDR_BIN_PATH:-herdr}" 2>/dev/null || true)"
if [[ -z $herdr_bin ]]; then
  exit 0
fi

# Mirrors the TypeScript path: only the socket variable reaches Herdr. --seq is
# omitted rather than built from date +%s%N, whose %N is a GNU extension that BSD
# date leaves as a literal; Herdr accepts a report without one.
clear_token() {
  [[ -n ${HERDR_PANE_ID:-} ]] || return 0
  local -a runner=(env -i)
  if [[ -n ${HERDR_SOCKET_PATH:-} ]]; then
    runner+=("HERDR_SOCKET_PATH=$HERDR_SOCKET_PATH")
  fi
  "${runner[@]}" "$herdr_bin" pane report-metadata "$HERDR_PANE_ID" \
    --source claude-cache --clear-token cache >/dev/null 2>&1 || true
}

if ! command -v deno >/dev/null 2>&1 || [[ ! -r $script ]]; then
  clear_token
  exit 0
fi

deno run \
  --no-prompt \
  --allow-read="$HOME/.config/claude/projects,$state" \
  --allow-write="$state" \
  --allow-env=HERDR_ENV,HERDR_PANE_ID,HERDR_SOCKET_PATH,HERDR_BIN_PATH,HOME \
  --allow-run="$herdr_bin" \
  "$script" "$@" || clear_token

exit 0
