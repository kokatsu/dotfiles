#!/usr/bin/env bash
# Entry point for herdr-cache-token, shared by the Stop, SessionStart and
# PostCompact hooks.
#
# Every check lives in the binary. This only covers the binary not running: a
# missing or failing binary clears the token rather than leaving one standing
# that nothing is maintaining, and the hook always exits 0 so a display-only
# hook never fails the turn.

# Herdr passes its own absolute store path. Preferring it over the bare name
# keeps the fallback working while a home-manager switch is swapping the profile.
herdr_bin="$(command -v "${HERDR_BIN_PATH:-herdr}" 2>/dev/null || true)"
if [[ -z $herdr_bin ]]; then
  exit 0
fi

# Mirrors the binary: only the socket variable reaches Herdr. --seq is omitted
# rather than built from date +%s%N, whose %N is a GNU extension that BSD date
# leaves as a literal; Herdr accepts a report without one.
clear_token() {
  [[ -n ${HERDR_PANE_ID:-} ]] || return 0
  local -a runner=(env -i)
  if [[ -n ${HERDR_SOCKET_PATH:-} ]]; then
    runner+=("HERDR_SOCKET_PATH=$HERDR_SOCKET_PATH")
  fi
  "${runner[@]}" "$herdr_bin" pane report-metadata "$HERDR_PANE_ID" \
    --source claude-cache --clear-token cache >/dev/null 2>&1 || true
}

if ! command -v herdr-cache-token >/dev/null 2>&1; then
  clear_token
  exit 0
fi

herdr-cache-token "$@" || clear_token

exit 0
