#!/usr/bin/env bash
set -eEuo pipefail

# gh-api-guard.sh をラッパーごと PreToolUse の入力で叩き、Deno の起動、権限指定、
# payload の読み取り、JSON の出力までが繋がっていることを判定 1 種につき 1 件で
# 確かめる。判定そのものは scripts/test-gh-api-guard.ts が gh-api-guard-cases.tsv
# で固定する。

report_failure() {
  local rc=$? line=$1
  printf '%s:%s: exit %s: %s\n' "${BASH_SOURCE[0]##*/}" "$line" "$rc" "$BASH_COMMAND" >&2
}
trap 'report_failure "$LINENO"' ERR

repo_root=$(git rev-parse --show-toplevel)
guard="$repo_root/.config/claude/hooks/gh-api-guard.sh"

pass=0
fail=0

check() {
  local id=$1 want_decision=$2 want_reason=$3 cmd=$4 out payload decision reason

  payload=$(jq -Rn --arg c "$cmd" '{tool_input: {command: $c}}')
  out=$(printf '%s' "$payload" | bash "$guard" 2>&1) || true

  if [[ $want_decision == none ]]; then
    decision=${out:+unexpected output}
    decision=${decision:-none}
    reason=""
    want_reason=""
  else
    decision=$(jq -r '.hookSpecificOutput.permissionDecision // "malformed"' <<<"$out" 2>/dev/null || echo malformed)
    reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$out" 2>/dev/null || echo "")
  fi

  if [[ $decision == "$want_decision" && $reason == *"$want_reason"* ]]; then
    pass=$((pass + 1))
    return
  fi
  fail=$((fail + 1))
  printf 'FAIL %s: %s\n  want %s / *%s*\n  got  %s / %s\n' \
    "$id" "$cmd" "$want_decision" "$want_reason" "$decision" "$reason" >&2
}

check allow allow "gh api: explicit GET" 'gh api repos/o/r -X GET'
check ask ask "HTTP method override to 'DELETE'" 'gh api repos/o/r -X DELETE'
check deny deny "gh api: no explicit HTTP method" 'gh api repos/o/r'
check none none - 'echo hello'

printf '=== gh-api-guard wrapper: %s cases, %s failures ===\n' "$((pass + fail))" "$fail"
[[ $fail -eq 0 ]]
