#!/usr/bin/env bash
# test-banned-commands.sh — check-banned-commands.sh のラッパーを検証する
#
# 判定そのものは scripts/test-check-banned-commands.ts が見る。ここで見るのは
# ラッパー自身の振る舞いである。
#   1. ラッパーから Deno と Herdr 入力ガードへ payload が渡り、判定が終了コードに戻ること
#   2. 壊れた payload、閉じた stdin、シグナル、書き込みの失敗でも exit 2 で落ちること

set -euo pipefail

HOOK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.config/claude/hooks" && pwd)/check-banned-commands.sh"
ERRORS=0
TESTS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
  TESTS=$((TESTS + 1))
  printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
  TESTS=$((TESTS + 1))
  ERRORS=$((ERRORS + 1))
  printf "${RED}  FAIL${NC} %s\n" "$1"
}

# フックに渡す JSON を生成
make_input() {
  jq -n --arg cmd "$1" '{"tool_input": {"command": $cmd}}'
}

# フックの終了コードを返す (0 = 許可、2 = ブロック、それ以外 = フック自体の異常)
hook_rc() {
  local rc=0
  make_input "$1" | bash "$HOOK_SCRIPT" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# make_input を通さず、生の payload をそのまま渡してブロックを検証する。
# JSON として壊れている入力を試すため、こちらだけ別経路にする。
assert_raw_blocked() {
  local payload="$1" label="$2" rc=0
  printf '%s' "$payload" | bash "$HOOK_SCRIPT" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "blocked: $label"
  else
    fail "should be blocked (exit 2), got exit $rc: $label"
  fi
}

# コマンドがブロックされることを検証 (厳密に exit 2)
assert_blocked() {
  local cmd="$1"
  local label="${2:-$cmd}"
  local rc
  rc=$(hook_rc "$cmd")
  if [ "$rc" -eq 2 ]; then
    pass "blocked: $label"
  else
    fail "should be blocked (exit 2), got exit $rc: $label"
  fi
}

# コマンドがパスすることを検証 (厳密に exit 0)
assert_allowed() {
  local cmd="$1"
  local label="${2:-$cmd}"
  local rc
  rc=$(hook_rc "$cmd")
  if [ "$rc" -eq 0 ]; then
    pass "allowed: $label"
  else
    fail "should be allowed (exit 0), got exit $rc: $label"
  fi
}

# 判定そのものは test-check-banned-commands.ts が見る。ここはラッパーから Deno へ
# payload が渡り、判定が終了コードに戻ることだけを確かめる。
echo "--- ラッパーから Deno までの結線 ---"
assert_blocked 'git fetch --depth 1'
assert_allowed 'git fetch'
echo ""

# ガード本体は test-herdr-peer-command-guard.sh が直接起動して検証する。ここは
# check-banned-commands.sh がガードを呼び続けていることだけを見る統合経路のテスト。
echo "--- Herdr 入力ガードの統合経路 ---"
assert_blocked 'herdr agent prompt "hello"'
assert_blocked 'herdr agent send-keys C-c'
assert_blocked 'herdr pane send-text hello'
assert_blocked 'herdr pane run ls'
assert_allowed 'herdr pane list' '入力系でない herdr サブコマンド'
assert_allowed 'herdr-peer ask codex "hello"' 'herdr-peer 経由'
echo ""

# 想定外の入力でも exit 2 でなければ Claude Code はコマンドを通す。
echo "--- 壊れた payload でも fail-closed であること ---"
assert_raw_blocked '{' '打ち切られた JSON'
assert_raw_blocked '' '空入力'
assert_raw_blocked '{"tool_input":null}' 'tool_input が null'
assert_raw_blocked '{"tool_input":{}}' 'command キーが無い'
assert_raw_blocked '{"tool_input":{"command":42}}' 'command が文字列でない'
echo ""

# payload を読む前に失敗する経路。fd 0 を閉じた状態では cat が制御端末へ落ちて
# ハングし、exit 2 を返さないどころか永久に戻らなかった。時間を区切って、
# 落ちること自体も検証する。
#
# 見張りを自前で持つのは、coreutils の timeout が macOS に無いからである。
#
# 終わらせるのが KILL なのは、フックが TERM を exit 2 へ変換するからで、
# TERM で殺すとハングがこの assert の PASS に化ける。KILL は捕まえられず、
# 137 をフックが騙ることはできない。
#
# 見張りの出力を捨てるのは、sleep が継承した stdout を握ったまま孤児になり、
# 出力がパイプなら読み手をその分待たせるからである。
echo "--- payload を読む前に失敗しても fail-closed であること ---"
assert_exit2_cmd() {
  local label="$1" rc=0 pid watchdog
  shift
  "$@" >/dev/null 2>&1 &
  pid=$!
  (
    sleep 20
    kill -KILL "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" || rc=$?
  kill -TERM "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  if [ "$rc" -eq 137 ]; then
    fail "timed out after 20s: $label"
  elif [ "$rc" -eq 2 ]; then
    pass "blocked: $label"
  else
    fail "should be blocked (exit 2), got exit $rc: $label"
  fi
}
assert_exit2_cmd 'stdin が閉じている' bash -c "exec 0<&-; bash '$HOOK_SCRIPT'"
assert_exit2_cmd 'stdin がディレクトリ' bash -c "bash '$HOOK_SCRIPT' < '$(dirname "$HOOK_SCRIPT")'"

# シェル変数も read -d '' も NUL を保持できない。payload を変数に載せていた頃は
# NUL の手前だけを検査して残りを捨てており、良性のコマンドを前に置けば通せた。
assert_exit2_cmd 'payload に NUL が混ざる' bash -c \
  "{ printf '%s' '{\"tool_input\":{\"command\":\"echo ok\"}}'; printf '\\0'; printf 'x'; } | bash '$HOOK_SCRIPT'"

# シグナルは 128+n で終わる。Claude Code はそれをブロックと見なさない。
# 書き手が止まっている間に来たシグナルで固まらないことも同時に見る。
#
# set -m が要る。ジョブ制御なしの非対話シェルは非同期の子の SIGINT を無視に
# 設定し、無視を継承したシグナルはトラップを張れない。Claude Code はフックを
# 前景の子として起動するので、ジョブ制御ありの方が実際の形に近い。
set -m
for sig in TERM HUP INT PIPE; do
  # A signal inherited as ignored cannot be trapped, so the launcher's
  # `trap 'exit 2' PIPE` is never installed under a parent that ignores it and
  # `kill -PIPE` then does nothing. That direction stays fail-closed by another
  # route (a write returns EPIPE, set -e takes it, normalize_exit returns 2),
  # but it is not this assertion, so say so rather than assert it falsely.
  if [[ $(trap -p "SIG$sig") == "trap -- '' SIG$sig" ]]; then
    printf '  SKIP SIG%s: 親が無視に設定しており、トラップを張れない\n' "$sig"
    continue
  fi
  fifo="$(mktemp -u)"
  mkfifo "$fifo"
  bash "$HOOK_SCRIPT" <"$fifo" >/dev/null 2>&1 &
  hook_pid=$!
  exec 9>"$fifo"
  sleep 0.3
  kill "-$sig" "$hook_pid" 2>/dev/null || true
  (
    sleep 5
    kill -KILL "$hook_pid" 2>/dev/null
  ) &
  watchdog=$!
  sig_rc=0
  wait "$hook_pid" 2>/dev/null || sig_rc=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  exec 9>&-
  rm -f "$fifo"
  if [ "$sig_rc" -eq 2 ]; then
    pass "blocked: SIG$sig を受けた"
  else
    fail "should be blocked (exit 2), got exit $sig_rc: SIG$sig を受けた"
  fi
done

# spooler が止まっていても cleanup が固まらないこと。TERM して wait する実装では、
# SIGSTOP された cat を永久に待ってフック全体がハングした。
probe_dir=$(mktemp -d)
mkfifo "$probe_dir/in"
TMPDIR="$probe_dir" bash "$HOOK_SCRIPT" <"$probe_dir/in" >/dev/null 2>&1 &
stuck_hook=$!
exec 9>"$probe_dir/in"
sleep 0.3
stuck_spool=$(pgrep -P "$stuck_hook" cat 2>/dev/null | head -1)
[[ -z $stuck_spool ]] || kill -STOP "$stuck_spool" 2>/dev/null || true
kill -TERM "$stuck_hook" 2>/dev/null || true
(
  sleep 5
  kill -KILL "$stuck_hook" 2>/dev/null
) &
stuck_watchdog=$!
stuck_rc=0
wait "$stuck_hook" 2>/dev/null || stuck_rc=$?
kill "$stuck_watchdog" 2>/dev/null || true
wait "$stuck_watchdog" 2>/dev/null || true
kill -CONT "$stuck_spool" 2>/dev/null || true
kill -KILL "$stuck_spool" 2>/dev/null || true
exec 9>&-
if [ "$stuck_rc" -eq 2 ]; then
  pass "blocked: spooler が停止していても cleanup が固まらない"
else
  fail "should be blocked (exit 2), got exit $stuck_rc: spooler が停止していても cleanup が固まらない"
fi
set +m
echo ""

# フックが書くのはブロック時だけなので、出力の失敗は判定を覆せない。ここで見るのは
# 「書き込みが失敗しても exit 2 のままで、141 などに化けないこと」である。
#
# fd を最初から閉じる (>&- 2>&-) のと、読み手が先に消えるのは別物である。前者の
# 書き込みエラーは EBADF、後者は EPIPE か SIGPIPE になる。両方を見る。
echo "--- 出力の書き込みが失敗しても判定が覆らないこと ---"
blocked_payload='{"tool_input":{"command":"git fetch --depth 1"}}'

assert_exit2_cmd '出力 fd が最初から閉じている (EBADF)' bash -c \
  "printf '%s' '$blocked_payload' | bash '$HOOK_SCRIPT' >&- 2>&-"

# head が即座に抜けて読み口が閉じるので、フックの書き込みは EPIPE になる。
# PIPESTATUS で見るのはフック自身の終了コードで、head のものではない。
broken_pipe_run="printf '%s' '$blocked_payload' | { bash '$HOOK_SCRIPT' 2>&1; } | head -c 0; exit \${PIPESTATUS[1]}"

assert_exit2_cmd '読み手が先に消える (EPIPE/SIGPIPE)' bash -c "$broken_pipe_run"
assert_exit2_cmd 'SIGPIPE 無視の親 + 読み手が先に消える' bash -c "trap '' PIPE; $broken_pipe_run"

allow_output=$(printf '%s' '{"tool_input":{"command":"echo hi"}}' | bash "$HOOK_SCRIPT" 2>&1)
if [ -z "$allow_output" ]; then
  pass "allowed: 通過時は 1 バイトも書かない"
else
  fail "通過時に出力があった: ${allow_output%%$'\n'*}"
fi
echo ""

echo "=== Results: $TESTS tests, $ERRORS failures ==="

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "ERROR: $ERRORS test(s) failed."
  exit 1
fi

echo "All tests passed."
