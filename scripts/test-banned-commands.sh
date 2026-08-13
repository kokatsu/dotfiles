#!/usr/bin/env bash
# shellcheck disable=SC2016  # テスト対象のコマンド文字列は展開させずそのまま渡す
# test-banned-commands.sh — check-banned-commands.sh の git shallow ガードを検証する
#
# 検証項目:
#   1. shallow 化する git fetch/pull がブロックされること (exit 2)
#      クォート付きフラグ・グローバルオプション・複数行/連結コマンドを含む
#   2. 誤検知しやすいコマンドが通過すること (exit 0)
#      clone --depth、submodule --depth、fetch/pull を含むコミットメッセージ・URL など

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

echo "=== Test: check-banned-commands.sh (git shallow guard) ==="
echo ""

echo "[shallow fetch/pull — should be blocked]"
assert_blocked "git fetch --depth 1"
assert_blocked "git fetch --depth=1 origin main"
assert_blocked "git pull --depth 1"
assert_blocked "git pull --depth=1 origin"
assert_blocked "git fetch --shallow-since=2020-01-01 origin"
assert_blocked "git fetch --shallow-exclude=v1.0 origin"
assert_blocked "git fetch --update-shallow"
assert_blocked 'git fetch "--depth" 1' "quoted flag: git fetch \"--depth\" 1"
assert_blocked "git fetch '--depth=1'" "quoted flag: git fetch '--depth=1'"
assert_blocked "git -C /repo fetch --depth 1" "global option: git -C /repo fetch --depth 1"
assert_blocked "git --no-pager pull --depth 1"
assert_blocked "true && git fetch --depth=1"
assert_blocked $'cd /tmp\ngit fetch --depth=1' "newline-separated: cd /tmp<NL>git fetch --depth=1"
assert_blocked 'git fetch --depth\=1 origin' 'escaped equals: git fetch --depth\=1 origin'
assert_blocked 'git fetch --dep\th=1 origin' 'escaped mid-flag: git fetch --dep\th=1 origin'
assert_blocked "git fetch \$'--depth' 1" "ansi-c quoted: git fetch \$'--depth' 1"
assert_blocked $'git fetch \\\n--depth 1' 'line continuation: git fetch \<NL>--depth 1'
assert_blocked 'echo "$(git fetch --depth 1)"' 'cmdsubst in dquotes: echo "$(git fetch --depth 1)"'
assert_blocked 'printf "%s\n" "$(git fetch --depth 1)"' 'cmdsubst in dquotes: printf "%s\n" "$(git fetch --depth 1)"'
assert_blocked 'echo "`git fetch --depth 1`"' 'backtick in dquotes: echo "`git fetch --depth 1`"'
assert_blocked $'cat <<EOF\n$(git pull --depth 1)\nEOF' 'cmdsubst in unquoted heredoc: cat <<EOF ... $(git pull --depth 1)'
assert_blocked 'FOO=1 git fetch --depth=1' 'env assignment prefix: FOO=1 git fetch --depth=1'
assert_blocked 'command git fetch --depth 1'
assert_blocked 'env git fetch --depth 1'
assert_blocked 'env -i FOO=bar git fetch --depth=1'
assert_blocked 'command env git pull --depth 1'
assert_blocked 'command -- git fetch --depth 1'
assert_blocked 'env -u FOO git fetch --depth 1'
assert_blocked 'env -C /tmp git fetch --depth 1'
assert_blocked "env -S 'git fetch --depth 1'"
assert_blocked "env -S '-i git fetch --depth 1'" "env option inside -S: env -S '-i git fetch --depth 1'"
assert_blocked "env -S '-u FOO git fetch --depth 1'" "env option inside -S: env -S '-u FOO git fetch --depth 1'"
assert_blocked "env --split-string='-i git fetch --depth 1'"
assert_blocked "env --split-string 'git fetch --depth 1'"
assert_blocked "env -S'git fetch --depth 1'"
assert_blocked "env -S'git\_fetch\_--depth\_1'"
assert_blocked "env -vS'git fetch --depth 1'"
assert_blocked "env -ivS'git fetch --depth 1'"
assert_blocked "env -S 'git\_fetch\_--depth\_1'" 'backslash-underscore separator: env -S git\_fetch\_--depth\_1'
assert_blocked "env --split-string='git\_fetch\_--depth=1'" 'backslash-underscore separator: env --split-string=git\_fetch\_--depth=1'
assert_blocked "env -S '-i\_git\_fetch\_--depth\_1'" 'env option via \_: env -S -i\_git\_fetch\_--depth\_1'
assert_blocked "env -S 'FOO=\"a\_b\" git fetch --depth 1'" 'dquoted \_ as in-arg space: env -S FOO="a\_b" git fetch --depth 1'
assert_blocked "env -S 'FOO=\"a b\" git fetch --depth 1'" "quoted value inside -S: env -S 'FOO=\"a b\" git fetch --depth 1'"
assert_blocked "git -C '/tmp/a b' fetch --depth 1" "space in option value: git -C '/tmp/a b' fetch --depth 1"
assert_blocked "env 'FOO=a b' git fetch --depth 1" "space in env value: env 'FOO=a b' git fetch --depth 1"
assert_blocked "env -C '/tmp/a b' git fetch --depth 1" "space in env -C value: env -C '/tmp/a b' git fetch --depth 1"
assert_blocked "git fetch \$'\\x2d\\x2ddepth' 1" "ansi-c hex escape: git fetch \$'\\x2d\\x2ddepth' 1"
assert_blocked "git fetch \$'\\055\\055depth' 1" "ansi-c octal escape: git fetch \$'\\055\\055depth' 1"
assert_blocked "git fetch \$'\\u2d\\u2d''depth' 1" "ansi-c \\u + concatenated quotes: git fetch \$'\\u2d\\u2d''depth' 1"
assert_blocked "git fetch \$'\\U0000002d\\U0000002ddepth' 1" "ansi-c \\U 8-digit: git fetch \$'\\U0000002d\\U0000002ddepth' 1"
assert_blocked 'echo hello && (' 'parse failure fails closed: echo hello && ('
echo ""

echo "[non-shallow / unrelated git — should be allowed]"
assert_allowed "git fetch"
assert_allowed "git fetch origin main"
assert_allowed "git pull origin main"
assert_allowed "git fetch --unshallow"
assert_allowed "git fetch --deepen=100"
assert_allowed "git clone --depth 1 https://example.com/repo.git"
assert_allowed "git clone https://github.com/foo/fetch.git --depth=1" "fetch in URL: git clone .../fetch.git --depth=1"
assert_allowed "git -C ~/pull clone --shallow-since=2020-01-01 https://example.com/x.git" "pull in path: git -C ~/pull clone --shallow-since=..."
assert_allowed 'git commit -m "ban git fetch --depth in hooks"' 'commit message: git commit -m "ban git fetch --depth in hooks"'
assert_allowed "git submodule update --init --depth 1"
assert_allowed 'git commit -m "mention; git fetch --depth 1 is forbidden"' 'quoted separator: git commit -m "mention; git fetch --depth 1 is forbidden"'
assert_allowed 'printf "%s\n" "git fetch --depth 1"' 'quoted command text: printf "%s\n" "git fetch --depth 1"'
assert_allowed "git fetch-pack --depth=1 host repo" "different command: git fetch-pack --depth=1"
assert_allowed 'git fetch origin main # --depth 1 is forbidden here' 'comment: git fetch origin main # --depth 1 ...'
assert_allowed $'cat <<\'EOF\'\ngit fetch --depth 1\nEOF' "quoted heredoc body: cat <<'EOF' ... git fetch --depth 1"
assert_allowed 'env FOO=bar printf ok' 'harmless wrapper: env FOO=bar printf ok'
assert_allowed 'command -v git' 'non-executing: command -v git'
assert_allowed "git fetch origin '--depth 1'" "flag-like single argument: git fetch origin '--depth 1'"
assert_allowed "env -S 'FOO=\"a b\" printenv FOO'" "harmless -S: env -S 'FOO=\"a b\" printenv FOO'"
assert_allowed "env -S 'printf\_<%s>\_ok'" 'harmless \_ args: env -S printf\_<%s>\_ok'
assert_allowed "env --split-string 'printf <%s> ok'" "harmless separate --split-string"
assert_allowed "env -S'printf <%s> ok'" "harmless attached -S"
assert_allowed "env -vS'printf <%s> ok'" "harmless combined -vS"
echo ""

echo "=== Results: $TESTS tests, $ERRORS failures ==="

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "ERROR: $ERRORS test(s) failed."
  exit 1
fi

echo "All tests passed."
