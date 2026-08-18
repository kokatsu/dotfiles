#!/usr/bin/env bash
# shellcheck disable=SC2016  # テスト対象のコマンド文字列は展開させずそのまま渡す
# test-banned-commands.sh — check-banned-commands.sh のガードを検証する
#
# 検証項目:
#   1. shallow 化する git fetch/pull がブロックされること (exit 2)
#      クォート付きフラグ・グローバルオプション・複数行/連結コマンドを含む
#   2. 誤検知しやすいコマンドが通過すること (exit 0)
#      clone --depth、submodule --depth、fetch/pull を含むコミットメッセージ・URL など
#   3. git identity の書き込みがブロックされ、読み取りが通過すること
#   4. AST コマンドガード (rm/eval/dd/mkfs/chmod/shred/grep -r/git 系) が
#      改行・then/do・ラッパー・バッククォート等の全経路でブロックし、
#      引数位置やコミットメッセージ内の語には誤検知しないこと

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

echo "--- git identity guard: 書き込みがブロックされること ---"
assert_blocked "git config user.email foo@example.com"
assert_blocked "git config --global user.name someone"
assert_blocked "git config --local user.email 'foo@example.com'"
assert_blocked "git -c user.email=foo@example.com commit -m x"
assert_blocked "git commit --amend --no-edit --author=\"foo <foo@example.com>\"" 'git commit --amend --author=...'
assert_blocked "git -C /repo commit --author 'foo <foo@example.com>' -m x"
assert_blocked "GIT_AUTHOR_EMAIL=foo@example.com git commit -m x"
assert_blocked "env GIT_COMMITTER_NAME=foo git commit -m x"
assert_blocked "true && git config user.email foo@example.com"
assert_blocked "git rebase --root --exec 'git commit --amend --author=\"foo <f@e.com>\"'" 'rebase --exec wrapping an author rewrite'
echo ""

echo "--- git identity guard: 読み取りは通過すること ---"
assert_allowed "git config --get user.email"
assert_allowed "git config --show-origin user.name"
assert_allowed "git config --get user.email && echo done" 'read then chained command'
assert_allowed "git config --list"
assert_allowed "git log --author=kokatsu -5" 'log filter: git log --author=kokatsu'
assert_allowed "git log --format='%an <%ae>' -1" 'log format showing author'
echo ""

echo "--- AST command guard: 全経路でブロックされること ---"
assert_blocked "rm -rf /tmp/x" 'plain rm'
assert_blocked $'set -x\nrm -rf /tmp/x' 'newline-separated rm'
assert_blocked "if true; then rm -rf /tmp/x; fi" 'rm after then'
assert_blocked "for f in a; do rm \$f; done" 'rm after do'
assert_blocked "command rm x" 'command rm'
assert_blocked "env rm x" 'env rm'
assert_blocked "sudo rm x" 'sudo rm'
assert_blocked "sudo -u root rm x" 'sudo -u root rm'
assert_blocked "sudo -r staff_r rm x" 'sudo -r role rm'
assert_blocked "sudo -t staff_t rm x" 'sudo -t type rm'
assert_blocked "sudo -a bsdauth rm x" 'sudo -a style rm'
assert_blocked "sudo --chdir /tmp rm x" 'sudo --chdir (分離引数) rm'
assert_blocked "sudo -nu root rm x" 'sudo -nu (クラスタ末尾が引数付き) rm'
assert_blocked "sudo -nr staff_r rm x" 'sudo -nr (クラスタ末尾が引数付き) rm'
assert_blocked "doas rm x" 'doas rm'
assert_blocked "exec rm x" 'exec rm'
assert_blocked "exec -ca fake rm x" 'exec -ca (クラスタ内 -a) rm'
assert_blocked 'builtin eval "echo hi"' 'builtin eval'
assert_blocked 'builtin -- eval "echo hi"' 'builtin -- eval'
assert_blocked "grep -re foo ." 'grep -re (e より前の r は再帰)'
assert_blocked "command -pp rm x" 'command -pp (クラスタ) rm'
assert_blocked "command -- rm x" 'command -- rm'
assert_blocked "env -iu FOO rm x" 'env -iu (クラスタ末尾 -u) rm'
assert_blocked "env -vC /tmp rm x" 'env -vC (クラスタ末尾 -C) rm'
assert_blocked "grep -r2 foo ." 'grep -r2 (数字入りクラスタ)'
assert_blocked "grep -2r foo ." 'grep -2r (数字入りクラスタ)'
assert_blocked "grep -n2r foo ." 'grep -n2r (数字入りクラスタ)'
assert_blocked "chmod -R 777 -- --reference" 'chmod -R 777 -- --reference (-- 後はファイル名)'
assert_blocked "chmod --rec 777 dir" 'chmod --rec (--recursive の省略形) 777'
assert_blocked "grep --rec foo ." 'grep --rec (--recursive の省略形)'
assert_blocked "grep --dereference-recursive foo ." 'grep --dereference-recursive'
assert_blocked "grep --regexp=foo -r ." 'grep --regexp=foo -r (attached 値の後の -r は再帰)'
assert_blocked "grep --directories=read -r ." 'grep --directories=read -r (attached 値の後の -r は再帰)'
assert_blocked "git clean --for -d" 'git clean --for (--force の省略形) -d'
assert_blocked "git diff -- --no-ext-diff" 'git diff -- --no-ext-diff (pathspec はガードを解除しない)'
assert_blocked "git clean -e -- -fd" 'git clean -e -- -fd (-- は -e の値)'
assert_blocked "git clean --exclude -- -fd" 'git clean --exclude -- -fd (-- は値)'
assert_blocked "git fetch --upload-pack -- --depth 1" 'git fetch --upload-pack -- --depth (-- は値)'
assert_blocked "git push --receive-pack -- --force" 'git push --receive-pack -- --force (-- は値)'
assert_blocked "git clean -qe -- -fd" 'git clean -qe -- -fd (クラスタ末尾 -e の値が --)'
assert_blocked "git fetch -vo -- --depth 1" 'git fetch -vo -- --depth (クラスタ末尾 -o の値が --)'
assert_blocked "git push -vo -- --force" 'git push -vo -- --force (クラスタ末尾 -o の値が --)'
assert_blocked "git push -fq origin main" 'git push -fq (クラスタ内 -f)'
assert_blocked "git clean -fde pattern" 'git clean -fde (f と d は実フラグ)'
assert_blocked "git diff --output --no-ext-diff" 'git diff --output --no-ext-diff (値はガードを解除しない)'
assert_blocked "git log -p -G --no-ext-diff" 'git log -p -G --no-ext-diff (-G の値はガードを解除しない)'
assert_blocked "git log -p --decorate-refs --no-ext-diff" 'git log -p --decorate-refs --no-ext-diff (値はガードを解除しない)'
assert_blocked "git log -p --decorate-refs-exclude --no-ext-diff" 'git log -p --decorate-refs-exclude --no-ext-diff (値はガードを解除しない)'
assert_blocked "git diff -U -- --no-ext-diff" 'git diff -U -- --no-ext-diff (裸 -U は -- を消費しない)'
assert_blocked "git diff --unified -- --no-ext-diff" 'git diff --unified -- (裸で有効)'
assert_blocked "git log -p --pretty -- --no-ext-diff" 'git log -p --pretty -- (裸で有効)'
assert_blocked "git log -pu -1" 'git log -pu (クラスタ内 -p)'
assert_blocked "git log -qp -1" 'git log -qp (クラスタ内 -p)'
assert_blocked "git log -pU3 -1" 'git log -pU3 (クラスタ内 -p + attached -U)'
assert_blocked "git push -fofoo-bar origin main" 'git push -fofoo-bar (記号入り attached 値の前の -f)'
assert_blocked "git clean -fdefoo-bar" 'git clean -fdefoo-bar (記号入り attached 値の前の -fd)'
assert_blocked "git log -pSfoo-bar -1" 'git log -pSfoo-bar (記号入り attached 値の前の -p)'
assert_blocked "chmod 777 -- --reference /" 'chmod 777 -- --reference / (-- 後はファイル名)'
assert_blocked 'echo `rm x`' 'backtick rm'
assert_blocked 'echo "$(rm x)"' 'cmdsubst rm'
assert_blocked '"rm" -rf x' 'quoted command name rm'
assert_blocked 'eval "echo hi"' 'eval'
assert_blocked "shred secret.txt" 'shred'
assert_blocked "mkfs.ext4 /dev/sdb" 'mkfs.ext4'
assert_blocked "dd if=/dev/zero of=/dev/sda" 'dd of=/dev/'
assert_blocked "chmod -R 777 dir" 'chmod -R 777'
assert_blocked "chmod 777 /" 'chmod 777 /'
assert_blocked "git push -f origin main" 'git push -f'
assert_blocked "git push origin main --force" 'git push --force (末尾)'
assert_blocked "git clean -fd" 'git clean -fd'
assert_blocked "git clean -f -d" 'git clean -f -d (分割フラグ)'
assert_blocked "git clean --force -x" 'git clean --force -x'
assert_blocked "git reset --hard origin/main" 'git reset --hard origin/main'
assert_blocked "git reset --hard HEAD~1" 'git reset --hard HEAD~1'
assert_blocked "grep -r foo ." 'grep -r'
assert_blocked "grep --recursive foo ." 'grep --recursive'
assert_blocked "egrep -Rn foo ." 'egrep -Rn'
echo ""

echo "--- AST command guard: 誤検知しないこと ---"
assert_allowed "rmdir empty-dir" 'rmdir (rm と別コマンド)'
assert_allowed "echo rm" 'rm が引数位置'
assert_allowed "gomi /tmp/x" 'gomi'
assert_allowed 'git commit -m "rm old files"' 'コミットメッセージ内の rm'
assert_allowed $'cat <<\'EOF\'\nrm -rf /\nEOF' 'quoted heredoc 本文の rm'
assert_allowed 'git log origin/main -1' 'origin/ 参照の読み取り'
assert_allowed "chmod -R 755 dir" 'chmod -R 755'
assert_allowed "chmod 777 file" 'chmod 777 (非再帰・非ルート)'
assert_allowed "git push --force-with-lease origin main" 'git push --force-with-lease'
assert_allowed "git clean -n" 'git clean -n (dry-run)'
assert_allowed "git reset --hard" 'git reset --hard (現 HEAD)'
assert_allowed "grep -n foo file" 'grep -n (非再帰)'
assert_allowed "grep -- -r file" 'grep -- -r (-- 以降はオペランド)'
assert_allowed "grep -e -r file" 'grep -e -r (-r はパターン)'
assert_allowed "grep -f -R file" 'grep -f -R (-R はパターンファイル)'
assert_allowed "grep -er file" 'grep -er (attached オペランド r)'
assert_allowed "grep -fr file" 'grep -fr (attached オペランド r)'
assert_allowed "grep -eerror file" 'grep -eerror (attached パターン)'
assert_allowed "grep -nfpatterns file" 'grep -nfpatterns (attached ファイル)'
assert_allowed "grep -dread foo file" 'grep -dread (attached アクション)'
assert_allowed "grep -Dread foo file" 'grep -Dread (attached アクション)'
assert_allowed "grep -d read foo file" 'grep -d read (分離アクション)'
assert_allowed "chmod 777 -- -R" 'chmod 777 -- -R (-R はファイル名)'
assert_allowed "command -- -p rm x" 'command -- -p (コマンド名が -p)'
assert_allowed "chmod --reference 777 -R dir" 'chmod --reference 777 (777 は参照ファイル)'
assert_allowed "chmod -R --reference 777 dir" 'chmod -R --reference 777 (777 は参照ファイル)'
assert_allowed "chmod --reference ref -R 777" 'chmod --reference ref -R 777 (777 は対象パス)'
assert_allowed "chmod -R --reference=ref 777" 'chmod -R --reference=ref 777 (777 は対象パス)'
assert_allowed "chmod --ref ref -R 777" 'chmod --ref (--reference の省略形) ref -R 777'
assert_allowed "chmod -R --ref=ref 777" 'chmod -R --ref=ref (省略形+attached) 777'
assert_allowed "grep --reg -r file" 'grep --reg -r (-r は --regexp のオペランド)'
assert_allowed "git clean -n -d -- --force" 'git clean -n -d -- --force (--force は pathspec)'
assert_allowed "git reset -- --hard origin/main" 'git reset -- --hard (pathspec)'
assert_allowed "git push -- --force" 'git push -- --force (--force は refspec)'
assert_allowed "git fetch -- --depth" 'git fetch -- --depth (refspec)'
assert_allowed "git push -of origin main" 'git push -of (f は -o の attached 値)'
assert_allowed "git push -vof origin main" 'git push -vof (f は -o の attached 値)'
assert_allowed "git clean -efd" 'git clean -efd (fd は -e の attached 値)'
assert_allowed "git clean -fed pattern" 'git clean -fed (d は -e の attached 値、-d なし)'
assert_allowed "rg -r replacement foo" 'rg -r (置換オプション)'
echo ""

echo "=== Results: $TESTS tests, $ERRORS failures ==="

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "ERROR: $ERRORS test(s) failed."
  exit 1
fi

echo "All tests passed."
