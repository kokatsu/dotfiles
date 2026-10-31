#!/usr/bin/env zsh
# zeno-start-server must record the PID of the server it starts even when
# ZENO_PID still names a server that was stopped from outside (the zsh.nix
# onChange hook does that), or zeno-stop-server later misses the new server.
emulate -R zsh

plugin=${1:?usage: test-zeno-restart.zsh <plugin-directory>}
tmp=$(mktemp -d)
export HOME=$tmp ZENO_ROOT=$plugin ZENO_SOCK=$tmp/zeno.sock
export XDG_CONFIG_HOME=$tmp/config XDG_DATA_HOME=$tmp/data
export XDG_CACHE_HOME=$tmp/cache XDG_STATE_HOME=$tmp/state
export DENO_DIR=$tmp/deno-cache ZENO_HOME=$tmp/config/zeno
export ZENO_DISABLE_AUTOMATIC_WORKSPACE_LOOKUP=1
mkdir -p $ZENO_HOME

# zeno-start-server discards the server's output; keep it for failure messages.
export ZENO_SERVER_BIN=$tmp/zeno-server
print -r -- "#!/bin/sh
exec '$plugin/bin/zeno-server' 2>>'$tmp/server.log'" > $ZENO_SERVER_BIN
chmod +x $ZENO_SERVER_BIN

first=
cleanup() {
  [[ -n $first ]] && kill $first 2>/dev/null
  # Ask the server for its PID: ZENO_PID is stale exactly when this test fails.
  if [[ -S $ZENO_SOCK ]]; then
    ZENO_PID=
    zeno-set-pid 2>/dev/null
    [[ -n $ZENO_PID ]] && kill $ZENO_PID 2>/dev/null
  fi
  rm -rf $tmp
}
trap cleanup EXIT

fail() {
  print -u2 -- "test-zeno-restart: $1"
  [[ -s $tmp/server.log ]] && cat $tmp/server.log >&2
  exit 1
}

fpath=($plugin/shells/zsh/functions $fpath)
autoload -Uz zeno-enable-sock
zeno-enable-sock

# Start the first server like a running shell would have, with a longer wait
# than zeno-start-server allows: a cold Deno start in the build sandbox can
# exceed it. The restart below then runs with warm caches.
$ZENO_SERVER_BIN >/dev/null 2>&1 &!
for i in {1..200}; do
  [[ -S $ZENO_SOCK ]] && break
  sleep 0.1
done
zeno-set-pid
first=$ZENO_PID
[[ -n $first ]] || fail 'first server did not start'

kill $first
for i in {1..100}; do
  kill -0 $first 2>/dev/null || break
  sleep 0.1
done
kill -0 $first 2>/dev/null && fail "first server ($first) did not exit"

zeno-start-server || fail 'second server did not start'
[[ $ZENO_PID != $first ]] || fail "ZENO_PID still names the stopped server ($first)"
kill -0 $ZENO_PID 2>/dev/null || fail "ZENO_PID ($ZENO_PID) is not a running server"

print 'zeno restart: ZENO_PID follows the restarted server'
