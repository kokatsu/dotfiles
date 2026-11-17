#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cat >"$workdir/codex" <<'MOCK'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$CODEX_LAUNCH_ARGS"
printf '%s' "${HERDR_PANE_ID:-}" >"$CODEX_LAUNCH_PANE"
exit "${CODEX_LAUNCH_STATUS:-0}"
MOCK
chmod +x "$workdir/codex"
export CODEX_LAUNCH_ARGS="$workdir/args" CODEX_LAUNCH_PANE="$workdir/pane"
launch() { bash "$repo_root/scripts/codex-launch.sh" "$workdir/codex" "$@"; }
HERDR_ENV=1 HERDR_PANE_ID=current-pane launch resume thread-one
printf '%s\0' --no-daemon resume thread-one >"$workdir/expected"
cmp "$workdir/args" "$workdir/expected"
[[ $(cat "$workdir/pane") == current-pane ]]
HERDR_ENV=0 launch resume 'thread with spaces'
printf '%s\0' resume 'thread with spaces' >"$workdir/expected"
cmp "$workdir/args" "$workdir/expected"
for flag in --no-daemon --remote=unix:///tmp/explicit.sock; do
  HERDR_ENV=1 launch "$flag" resume thread-one
  printf '%s\0' "$flag" resume thread-one >"$workdir/expected"
  cmp "$workdir/args" "$workdir/expected"
done
HERDR_ENV=1 launch -- --no-daemon
printf '%s\0' --no-daemon -- --no-daemon >"$workdir/expected"
cmp "$workdir/args" "$workdir/expected"
status=0
HERDR_ENV=1 CODEX_LAUNCH_STATUS=23 launch --version || status=$?
[[ $status == 23 ]]
printf 'Codex launch: pane-local server, explicit options, arguments and exit status passed\n'
