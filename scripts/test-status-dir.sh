#!/usr/bin/env bash
set -euo pipefail

# bin/status-dir が Windows の実際のプロファイルを使い、解決できないときは同名の
# ディレクトリだけへ倒すことを、偽の cmd.exe、wslpath、uname で確かめる。

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

failures=0
# shellcheck source=scripts/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

mkdir -p "$test_dir/bin" "$test_dir/Profiles/Taro Yamada" "$test_dir/Profiles/A & B" "$test_dir/Users"
export TEST_DIR="$test_dir"
export USER=wsluser
export STATUS_DIR_CMD_EXE="$test_dir/bin/cmd.exe"
export STATUS_DIR_WSLPATH="$test_dir/bin/wslpath"
export STATUS_DIR_USERS_DIR="$test_dir/Users"
export PATH="$test_dir/bin:$PATH"

cat >"$test_dir/bin/cmd.exe" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == '/C set USERPROFILE' ]] || exit 1
printf '%s' "${TEST_VARS_BEFORE:-}"
[[ -z "$TEST_PROFILE" ]] || printf 'USERPROFILE=%s\r\n' "$TEST_PROFILE"
printf '%s' "${TEST_VARS_AFTER:-}"
exit "${TEST_CMD_STATUS:-0}"
MOCK
cat >"$test_dir/bin/wslpath" <<'MOCK'
#!/usr/bin/env bash
[[ $# -eq 2 && $1 == -u ]] || exit 1
[[ $2 == 'D:\'* ]] || exit 1
rest=${2#'D:\'}
printf '%s/%s\n' "$TEST_DIR" "${rest//\\//}"
MOCK
cat >"$test_dir/bin/uname" <<'MOCK'
#!/usr/bin/env bash
echo "$TEST_UNAME"
MOCK
chmod +x "$test_dir"/bin/*

export TEST_UNAME=Linux
export TEST_PROFILE='D:\Profiles\Taro Yamada'
fallback="$test_dir/Users/wsluser"

expect_path() {
  local actual
  actual=$("$repo_root/bin/status-dir" feed-watch) || actual="exit $?"
  if [[ "$actual" == "$2" ]]; then
    pass "$1"
  else
    fail "$1: expected $2, got $actual"
  fi
}

# 同名ディレクトリの有無の両方で、フォールバックの成否を見る
expect_fallback() {
  expect_path "$1: fails without a same-named directory" "exit 1"
  mkdir "$fallback"
  expect_path "$1: uses the same-named directory" "$fallback/.cache/feed-watch"
  rmdir "$fallback"
}

profile_cache="$test_dir/Profiles/Taro Yamada/.cache/feed-watch"
mkdir "$fallback"
expect_path "profile with a space wins over the same-named directory" "$profile_cache"
rmdir "$fallback"

TEST_VARS_BEFORE=$'USERPROFILE1=D:\\Users\r\n' TEST_VARS_AFTER=$'USERPROFILE_OLD=D:\\Users\r\n' \
  expect_path "variables sharing the prefix" "$profile_cache"
TEST_PROFILE='D:\Profiles\A & B' expect_path "profile with an ampersand" "$test_dir/Profiles/A & B/.cache/feed-watch"

STATUS_DIR_CMD_EXE="$test_dir/missing" expect_fallback "cmd.exe cannot run"
TEST_PROFILE='' expect_fallback "empty output"
TEST_PROFILE='' TEST_VARS_AFTER=$'USERPROFILE_OLD=D:\\Users\r\n' expect_fallback "only a variable sharing the prefix"
TEST_CMD_STATUS=7 expect_fallback "cmd.exe fails after printing a profile"
TEST_PROFILE='' TEST_CMD_STATUS=1 expect_fallback "undefined variable"
STATUS_DIR_WSLPATH="$test_dir/missing" expect_fallback "wslpath cannot run"
TEST_PROFILE='E:\Profiles' expect_fallback "wslpath fails"
TEST_PROFILE='D:\Profiles\missing' expect_fallback "profile directory does not exist"

TEST_UNAME=Darwin HOME="$test_dir/home" expect_path "macOS uses HOME" "$test_dir/home/.cache/feed-watch"

if [[ $failures -gt 0 ]]; then
  echo "status-dir tests: $failures failure(s)" >&2
  exit 1
fi
echo "status-dir tests passed"
