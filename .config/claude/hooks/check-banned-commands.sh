#!/usr/bin/env bash
# Launcher for check-banned-commands.ts.
#
# It exists so settings.json names one command per hook, so the Deno permission
# set can be built from paths this script resolves, and so the Herdr input guard
# keeps running as a separate file that Codex registers on its own.
#
# Unlike herdr-cache-token.sh, which is display-only and exits 0 when Deno is
# missing, every failure here exits 2. This hook is a guard: a missing
# dependency must block the command, not wave it through. Claude Code treats
# only exit 2 as blocking, so exiting nonzero any other way would fail open.
set -euo pipefail

# Backstop for everything, including the lines below that run before any
# explicit check: reading stdin, resolving HOOKS_DIR, or any command this
# script gains later. Installed first so nothing executes outside its reach.
payload=""
spool=""

normalize_exit() {
  local status=$?
  # The spooler outlives a signalled launcher otherwise: it is reparented to
  # init and keeps writing into an unlinked inode until its writer closes.
  #
  # KILL rather than TERM, and no `wait`: a stopped or unresponsive spooler
  # would leave `wait` blocking forever, turning cleanup into the hang this
  # whole path exists to avoid. Not reaping it is also what makes the kill
  # safe — an unreaped child keeps its PID, so it cannot have been recycled.
  [[ -z $spool ]] || kill -KILL "$spool" 2>/dev/null || true
  [[ -z $payload ]] || rm -f -- "$payload"
  case $status in
  0 | 2) exit "$status" ;;
  esac
  printf 'banned-commands hook exited %s before reaching a verdict; refusing to run the command unchecked.\n' \
    "$status" >&2
  exit 2
}
trap normalize_exit EXIT

# A signal leaves the shell with 128+n, which Claude Code does not read as a
# block. Convert to 2 and let the EXIT trap clean up. KILL and STOP cannot be
# caught, so those stay outside what this script can promise.
#
# A signal the parent already ignores cannot be trapped either: the trap below
# is simply not installed for it. SIGPIPE is the case that matters, and it is
# harmless here for a reason that does not depend on the trap at all. This hook
# writes nothing on the allow path, so the only writes it ever makes are on
# paths that have already decided to block. A failed write there cannot turn a
# block into an allow; `set -e` and normalize_exit still land on 2.
trap 'exit 2' HUP INT PIPE TERM

refuse() {
  printf 'banned-commands hook cannot run (%s); refusing to run the command unchecked.\n' "$1" >&2
  exit 2
}

HOOKS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$HOOKS_DIR/check-banned-commands.ts"

# stdin is consumed by the first reader, and both the guard and the TypeScript
# need the same payload, so spool it once and redirect each from the file.
#
# A shell variable cannot hold a NUL, so a payload containing one would be
# truncated and only its prefix checked.
#
# A terminal on stdin means this was not invoked by Claude Code; reading it
# would hang.
[[ -t 0 ]] && refuse "stdin is a terminal, not a piped payload"

payload=$(mktemp) || refuse "could not create a temporary file"

# Spool in the background and wait. A trapped signal is only delivered between
# commands, so signalling the launcher while a foreground `cat` blocks on a
# stalled writer would leave it hanging until the writer moved. `wait` is
# interruptible, which is what makes the signal traps above effective.
#
# fd 3 carries stdin in explicitly: a non-interactive shell redirects an
# asynchronous command's stdin from /dev/null, so a bare `cat &` would spool an
# empty payload and every command would read as malformed.
exec 3<&0
cat <&3 >"$payload" &
spool=$!
wait "$spool" || refuse "could not read the payload from stdin"
spool=""
exec 3<&-

# Open both readers, then unlink. The payload is the command text verbatim and
# may carry credentials, and a named file would survive a SIGKILL or a power
# loss; unlinking now bounds that to the spool itself. Each fd keeps its own
# offset, so both consumers read from the start.
exec 4<"$payload" 5<"$payload"
rm -f -- "$payload"
payload=""

# Every dependency is checked before anything runs, including jq for the guard
# below: without it the guard dies with 127 and takes this script with it.
[[ -r $script ]] || refuse "cannot read $script"

shfmt_bin="$(command -v shfmt || true)"
[[ -n $shfmt_bin ]] || refuse "shfmt not found"

command -v jq >/dev/null 2>&1 || refuse "jq not found"
command -v deno >/dev/null 2>&1 || refuse "deno not found"

# 0 passes through, 2 is a real verdict, anything else is a failure to check.
normalize() {
  local status=$1 what=$2
  case $status in
  0 | 2) return "$status" ;;
  *) refuse "$what exited $status" ;;
  esac
}

# Best-effort Herdr command guard, shared with Codex (which registers
# herdr-peer-command-guard.sh directly from nix/home/programs/codex.nix instead
# of running this script). It prevents ordinary bypasses but is not a security
# boundary for arbitrary Bash access.
[[ -r $HOOKS_DIR/herdr-peer-command-guard.sh ]] || refuse "cannot read the Herdr guard"
guard_status=0
bash "$HOOKS_DIR/herdr-peer-command-guard.sh" <&4 5<&- || guard_status=$?
normalize "$guard_status" "the Herdr guard"

# Not exec: the exit status has to come back here to be normalized. A Deno
# startup failure, a permission denial, or an uncaught exception all land on
# codes Claude Code would let through.
deno_status=0
deno run \
  --no-prompt \
  --allow-read="$HOOKS_DIR" \
  --allow-run="$shfmt_bin" \
  "$script" "$shfmt_bin" <&5 4<&- || deno_status=$?
normalize "$deno_status" "the banned-commands check"
