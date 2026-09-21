#!/usr/bin/env bash
set -euo pipefail

# .config/codex/hooks/gh-api-method-required.sh を PreToolUse の入力で叩き、
# 「本物の gh api 呼び出しだけを見て、メソッド未指定なら exit 2」を固定する。

repo_root=$(git rev-parse --show-toplevel)
hook="$repo_root/.config/codex/hooks/gh-api-method-required.sh"
fail=0

check() {
  local want=$1 cmd=$2 rc=0
  jq -Rn --arg c "$cmd" '{tool_input: {command: $c}}' | bash "$hook" >/dev/null 2>&1 || rc=$?
  if [[ $rc == "$want" ]]; then
    printf '  PASS exit %s: %s\n' "$rc" "$cmd"
  else
    printf '  FAIL want %s got %s: %s\n' "$want" "$rc" "$cmd" >&2
    fail=1
  fi
}

# 本物の呼び出し
check 2 'gh api repos/o/r'
check 2 'gh api -H "Accept: x" repos/o/r'
check 2 'env GH_HOST=x gh api repos/o/r'
check 2 'sudo -u me gh api repos/o/r'
check 2 'timeout 5 gh api repos/o/r'
check 2 'cd repo && gh api repos/o/r'
check 2 '/opt/homebrew/bin/gh api repos/o/r'
check 2 'gh api -X GET a && gh api -X GET b'
check 0 'gh api -X GET repos/o/r'
check 0 'gh api --method POST repos/o/r/issues'
check 0 'GH_HOST=x gh api -X GET repos/o/r'

# 地の文や引数の中に現れるだけのもの
check 0 'echo "run gh api later"'
check 0 'git commit -m "use gh api instead of curl"'
check 0 'rg "gh api" docs/'
check 0 'echo done'

if [[ $fail -ne 0 ]]; then
  exit 1
fi
printf 'gh api method hook tests passed\n'
