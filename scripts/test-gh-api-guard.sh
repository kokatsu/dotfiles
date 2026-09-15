#!/usr/bin/env bash
set -eEuo pipefail

# scripts/gh-api-guard-cases.tsv の各行を PreToolUse の入力として食わせ、
# 判定と理由を突き合わせる。フックを外から叩くだけなので、実装言語が変わっても
# 同じケース表がそのまま使える。

report_failure() {
  local rc=$? line=$1
  printf '%s:%s: exit %s: %s\n' "${BASH_SOURCE[0]##*/}" "$line" "$rc" "$BASH_COMMAND" >&2
}
trap 'report_failure "$LINENO"' ERR

repo_root=$(git rev-parse --show-toplevel)
guard="$repo_root/.config/claude/hooks/gh-api-guard.sh"
cases="$repo_root/scripts/gh-api-guard-cases.tsv"

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

while IFS=$'\t' read -r id decision reason cmd; do
  [[ -n $id && $id != \#* ]] || continue
  check "$id" "$decision" "$reason" "$cmd"
done <"$cases"

printf '=== gh-api-guard: %s cases, %s failures ===\n' "$((pass + fail))" "$fail"
[[ $fail -eq 0 ]]
