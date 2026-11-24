#!/usr/bin/env bash
set -euo pipefail

# bin/ime-watch と bin/slack-watch の install が、失敗しても旧版を失わないことを、
# 偽の dotnet、cmd.exe、reg.exe、tasklist.exe、wslpath で確かめる。

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

failures=0
# shellcheck source=scripts/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

bin="$test_dir/bin"
mkdir -p "$bin"
REAL_MV=$(command -v mv)
REAL_SLEEP=$(command -v sleep)
export TEST_DIR="$test_dir" REAL_MV REAL_SLEEP
export IME_WATCH_DOTNET="$bin/dotnet" SLACK_WATCH_DOTNET="$bin/dotnet"
export SLACK_WATCH_INTERVAL=1
export WINDOWS_WATCH_CMD_EXE="$bin/cmd.exe"
export WINDOWS_WATCH_REG_EXE="$bin/reg.exe"
export WINDOWS_WATCH_TASKLIST_EXE="$bin/tasklist.exe"
export WINDOWS_WATCH_WSLPATH="$bin/wslpath"
export PATH="$bin:$PATH"

cat >"$bin/cmd.exe" <<'MOCK'
#!/usr/bin/env bash
printf 'USERPROFILE=D:\\Taro & Co\r\n'
MOCK
cat >"$bin/wslpath" <<'MOCK'
#!/usr/bin/env bash
if [[ $1 == -u ]]; then
  rest=${2#'D:\'}
  printf '%s/%s\n' "$TEST_DIR" "${rest//\\//}"
else
  [[ -z "${TEST_WSLPATH_FAIL:-}" ]] || exit 1
  [[ -n "${TEST_WSLPATH_EMPTY:-}" ]] || printf 'W:%s\n' "$2"
fi
MOCK
cat >"$bin/reg.exe" <<'MOCK'
#!/usr/bin/env bash
[[ -z "${TEST_REG_FAIL:-}" ]] || exit 1
printf '%s\n' "$@" >"$TEST_DIR/run-key"
MOCK
# daemon があれば常駐プロセスがいる。中身は版。停止すると先に PID ファイルが消え、
# プロセスは linger の回数だけ確認された後に終わる
cat >"$bin/tasklist.exe" <<'MOCK'
#!/usr/bin/env bash
[[ -z "${TEST_TASKLIST_FAIL:-}" ]] || exit 1
pid=${2#PID eq }
state="$TEST_DIR/Taro & Co/.cache/$TEST_NAME"
if [[ -f "$state/stop.request" && ! -f "$TEST_DIR/linger" && -z "${TEST_STUBBORN:-}" ]]; then
  rm -f "$state/stop.request" "$state/daemon.pid"
  echo "${TEST_LINGER:-0}" >"$TEST_DIR/linger"
fi
[[ -z "${TEST_TASKLIST_FAIL_WAITING:-}" || ! -f "$TEST_DIR/linger" ]] || exit 1
if [[ -f "$TEST_DIR/linger" ]]; then
  left=$(cat "$TEST_DIR/linger")
  if ((left == 0)); then
    rm -f "$TEST_DIR/linger" "$TEST_DIR/daemon"
  else
    echo $((left - 1)) >"$TEST_DIR/linger"
  fi
fi
if [[ -f "$TEST_DIR/daemon" && "$pid" == "$(cat "$TEST_DIR/pid")" ]]; then
  printf '\r\ndotnet.exe  %s Console  1  1,024 K\r\n' "$pid"
else
  printf 'INFO: No tasks are running which match the specified criteria.\r\n'
fi
MOCK
cat >"$bin/dotnet" <<'MOCK'
#!/usr/bin/env bash
to_path() { wslpath -u "$1"; }
if [[ $1 == publish ]]; then
  [[ -z "${TEST_PUBLISH_FAIL:-}" ]] || exit 1
  out=$(to_path "$5")
  mkdir -p "$out"
  [[ -n "${TEST_PUBLISH_EMPTY:-}" ]] || echo "$TEST_VERSION" >"$out/$TEST_ASSEMBLY.dll"
  exit 0
fi
dll=$(to_path "$1")
state="$TEST_DIR/Taro & Co/.cache/$TEST_NAME"
case $2 in
running)
  if [[ -n "${TEST_HOST_FAIL:-}" ]]; then
    echo 'host error' >&2
    exit 1
  fi
  [[ -z "${TEST_PID_VANISHES:-}" ]] || rm -f "$state/daemon.pid"
  [[ -f "$TEST_DIR/daemon" && "$(cat "$state/daemon.pid" 2>/dev/null)" == "$(cat "$TEST_DIR/pid"):1" ]] || exit 1
  ;;
watch)
  # 実物の Mutex と同じく、前のプロセスが残っていれば起動しない
  [[ ! -f "$TEST_DIR/daemon" ]] || exit 0
  cp "$dll" "$TEST_DIR/daemon"
  mkdir -p "$state"
  echo "$$" >"$TEST_DIR/pid"
  echo "$$:1" >"$state/daemon.pid"
  ;;
esac
MOCK
cat >"$bin/mv" <<'MOCK'
#!/usr/bin/env bash
if [[ -n ${TEST_OVERLAP:-} && $1 == */bin.new ]]; then
  if TEST_OVERLAP='' TEST_VERSION=3 "$TEST_OVERLAP" install >"$TEST_DIR/second-install.log" 2>&1; then
    echo "second install succeeded" >>"$TEST_DIR/events"
  else
    echo "second install refused" >>"$TEST_DIR/events"
  fi
fi
if [[ -n "${TEST_MV_FAIL:-}" && $1 == */"$TEST_MV_FAIL" ]]; then
  echo "mv: refused" >&2
  exit 1
fi
case ${!#} in
*/stop.request) echo stop-request >>"$TEST_DIR/events" ;;
*/bin.old) [[ ! -f "$TEST_DIR/daemon" ]] || echo swap-while-running >>"$TEST_DIR/events" ;;
esac
exec "$REAL_MV" "$@"
MOCK
cat >"$bin/sleep" <<'MOCK'
#!/usr/bin/env bash
exec "$REAL_SLEEP" 0.05
MOCK
cat >"$bin/setsid" <<'MOCK'
#!/usr/bin/env bash
exec "$@"
MOCK
chmod +x "$bin"/*

check() {
  local name=$1
  shift
  if "$@"; then
    pass "$TEST_NAME: $name"
  else
    fail "$TEST_NAME: $name"
  fi
}

run() { "$repo_root/bin/$TEST_NAME" "$@" >"$test_dir/log" 2>&1; }
start_fails() { ! run start; }
no_pid_file() { [[ ! -e "$state_dir/daemon.pid" ]]; }
no_stopping_file() { [[ ! -e "$state_dir/stopping.pid" ]]; }
install_fails() { ! run install; }
deployed_is() { [[ $(cat "$install_dir/bin/$TEST_ASSEMBLY.dll") == "$1" ]]; }
daemon_is() { [[ $(cat "$test_dir/daemon" 2>/dev/null) == "$1" ]]; }
no_daemon() { [[ ! -e "$test_dir/daemon" ]]; }
no_leftovers() { [[ ! -e "$install_dir/bin.old" && ! -e "$install_dir/bin.new" ]]; }
no_stop_request() { [[ ! -e "$state_dir/stop.request" ]]; }
never_stopped() { ! grep -q stop-request "$test_dir/events"; }
never_swapped_while_running() { ! grep -q swap-while-running "$test_dir/events"; }
run_key_unchanged() { cmp -s "$test_dir/run-key" "$test_dir/run-key.before"; }
run_key_is_set() {
  grep -qxF "\"W:$bin/dotnet\" \"D:\\Taro & Co\\AppData\\Local\\$TEST_NAME\\bin\\$TEST_ASSEMBLY.dll\" watch" "$test_dir/run-key"
}

reset() {
  rm -rf "$test_dir/Taro & Co" "$test_dir/daemon" "$test_dir/linger" "$test_dir/run-key"
  : >"$test_dir/events"
  mkdir -p "$test_dir/Taro & Co"
}

# 版 1 を配備して起動した状態を作り、以後の install は版 2 を作る
running_v1() {
  reset
  TEST_VERSION=1 run install
  run start
  # 配備の失敗時に Run キーが書き直されないことを見るため、実際の登録値と区別できる値にする
  echo before >"$test_dir/run-key"
  cp "$test_dir/run-key" "$test_dir/run-key.before"
  export TEST_VERSION=2
}

# install が失敗し、旧版が動き続ける
check_kept() {
  check "$1: install fails" install_fails
  check "$1: the old version stays deployed" deployed_is 1
  check "$1: the old version keeps running" daemon_is 1
  check "$1: the Run key is unchanged" run_key_unchanged
  check "$1: no stop request is left" no_stop_request
  check "$1: no swap under a running process" never_swapped_while_running
}

# 停止要求を出す前に失敗する
check_untouched() {
  check_kept "$1"
  check "$1: the old version is never asked to stop" never_stopped
}

check_retry() {
  check "$1: retry succeeds" run install
  check "$1: retry deploys the new version" deployed_is 2
  check "$1: retry sets the Run key" run_key_is_set
  check "$1: retry leaves nothing behind" no_leftovers
}

for pair in ime-watch:ImeWatch slack-watch:SlackWatch; do
  export TEST_NAME=${pair%:*} TEST_ASSEMBLY=${pair#*:}
  install_dir="$test_dir/Taro & Co/AppData/Local/$TEST_NAME"
  state_dir="$test_dir/Taro & Co/.cache/$TEST_NAME"

  reset
  export TEST_VERSION=1
  check "first install succeeds" run install
  check "first install deploys" deployed_is 1
  check "first install sets the Run key" run_key_is_set
  check "first install leaves nothing behind" no_leftovers
  check "first install starts nothing" no_daemon
  check "start succeeds" run start
  check "start runs the deployed version" daemon_is 1

  TEST_VERSION=2 TEST_OVERLAP="$repo_root/bin/$TEST_NAME" check "overlapping installs: first succeeds" run install
  check "overlapping installs: second is refused during the swap" grep -qxF "second install refused" "$test_dir/events"
  check "overlapping installs: first version is deployed in bin" deployed_is 2
  check "overlapping installs: no nested staging directory" test ! -e "$install_dir/bin/bin.new"

  running_v1
  check "update succeeds" run install
  check "update deploys the new version" deployed_is 2
  check "update stops the old version" no_daemon
  check "update leaves nothing behind" no_leftovers
  check "start after update succeeds" run start
  check "start after update runs the new version" daemon_is 2

  running_v1
  run stop
  check "update of a stopped version succeeds" run install
  check "update of a stopped version starts nothing" no_daemon

  running_v1
  TEST_PUBLISH_FAIL=1 check_untouched "publish failure"
  check_retry "publish failure"

  running_v1
  TEST_PUBLISH_EMPTY=1 check_untouched "publish without the DLL"
  check_retry "publish without the DLL"

  running_v1
  TEST_STUBBORN=1 check_kept "stop timeout"
  check_retry "stop timeout"

  running_v1
  TEST_HOST_FAIL=1 check_untouched "unknown state"
  check_retry "unknown state"

  running_v1
  TEST_TASKLIST_FAIL=1 check_untouched "tasklist failure"
  check_retry "tasklist failure"

  running_v1
  TEST_WSLPATH_FAIL=1 check_untouched "wslpath failure"
  check_retry "wslpath failure"

  running_v1
  TEST_WSLPATH_EMPTY=1 check_untouched "empty wslpath output"
  check_retry "empty wslpath output"

  running_v1
  TEST_LINGER=3 check "slow exit: update succeeds" run install
  check "slow exit: no swap under a running process" never_swapped_while_running

  running_v1
  TEST_LINGER=3 TEST_MV_FAIL=bin.new check_kept "swap failure after a slow exit"

  # PID ファイルは消えたがプロセスが終わらない
  running_v1
  TEST_LINGER=9999 check_kept "process outliving its PID file"
  check_kept "retry while that process is alive"
  rm "$test_dir/daemon" "$test_dir/linger"
  check_retry "retry after that process exits"

  # 停止待ちが期限切れになった後で PID ファイルが消える
  running_v1
  TEST_STUBBORN=1 check_kept "PID file vanishing during the check"
  TEST_PID_VANISHES=1 check_kept "retry while the PID file vanishes"

  running_v1
  TEST_STUBBORN=1 check_kept "PID file vanishing after the timeout"
  rm "$state_dir/daemon.pid"
  check_kept "retry after the PID file vanished"
  check "start is refused while that process is alive" start_fails
  check "the PID file is not recreated" no_pid_file
  rm "$test_dir/daemon"
  check_retry "retry after the vanished process exits"
  check "no stopping file is left" no_stopping_file

  running_v1
  TEST_TASKLIST_FAIL_WAITING=1 check_kept "tasklist failure while waiting"

  running_v1
  TEST_MV_FAIL=bin check_kept "failure moving the old version away"
  check_retry "failure moving the old version away"

  running_v1
  TEST_MV_FAIL=bin.new check_kept "failure moving the new version in"
  check_retry "failure moving the new version in"

  running_v1
  run stop
  TEST_MV_FAIL=bin.new check "swap failure while stopped: install fails" install_fails
  check "swap failure while stopped: starts nothing" no_daemon
  check "swap failure while stopped: restores" deployed_is 1

  running_v1
  TEST_REG_FAIL=1 check "Run key failure: install fails" install_fails
  check "Run key failure: the new version is deployed" deployed_is 2
  check_retry "Run key failure"

  # 旧版を退避した直後に中断した状態
  running_v1
  run stop
  "$REAL_MV" "$install_dir/bin" "$install_dir/bin.old"
  TEST_PUBLISH_FAIL=1 check "interrupted swap: install fails" install_fails
  check "interrupted swap: the old version is restored first" deployed_is 1
  check_retry "interrupted swap"

  running_v1
  rm "$install_dir/bin/$TEST_ASSEMBLY.dll"
  check "PID file without the DLL: install fails" install_fails
done

if [[ $failures -gt 0 ]]; then
  echo "windows-watch install tests: $failures failure(s)" >&2
  exit 1
fi
echo "windows-watch install tests passed"
