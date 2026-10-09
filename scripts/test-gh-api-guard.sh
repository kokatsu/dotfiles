#!/usr/bin/env bash
set -eEuo pipefail

# settings.json の gh-api フックのコマンドを、ビルドした agent-guard で
# PreToolUse の入力ごと叩く。コマンドが gh-api モードを起動し、判定が JSON と
# exit 0 で返ること、判定に届かなかった失敗でも exit 0 で判定を出さないことを
# 確かめる。判定そのものは tools/agent-guard の go test が
# testdata/gh-api-guard-cases.tsv で固定する。

report_failure() {
  local rc=$? line=$1
  printf '%s:%s: exit %s: %s\n' "${BASH_SOURCE[0]##*/}" "$line" "$rc" "$BASH_COMMAND" >&2
}
trap 'report_failure "$LINENO"' ERR

repo_root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(cd "$repo_root/tools/agent-guard" && go build -o "$work/bin/agent-guard" .)

hook_entry=$(jq -c '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]
  | select(.command | test("agent-guard gh-api"))]' "$repo_root/.config/claude/settings.json")

pass=0
fail=0

record() {
  if [[ $1 == ok ]]; then
    pass=$((pass + 1))
    return
  fi
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$2" >&2
}

if [[ $(jq length <<<"$hook_entry") == 1 && $(jq -r '.[0].if' <<<"$hook_entry") == 'Bash(gh api *)' ]]; then
  record ok
else
  record ng "settings.json: want one gh-api hook gated by Bash(gh api *), got $hook_entry"
fi

# Claude Code はフックのコマンドを /bin/sh に渡す。下の sh -c へは環境変数で渡す。
export HOOK_COMMAND
HOOK_COMMAND=$(jq -r '.[0].command' <<<"$hook_entry")

# run <PATH> <payload>: stdout、stderr、終了コードを別々に取る。
run() {
  rc=0
  PATH=$1 /bin/sh -c "$HOOK_COMMAND" <<<"$2" >"$work/out" 2>"$work/err" || rc=$?
  out=$(<"$work/out")
}

check() {
  local id=$1 want_decision=$2 want_reason=$3 cmd=$4 decision reason

  run "$work/bin:$PATH" "$(jq -cn --arg c "$cmd" '{tool_input: {command: $c}}')"

  if [[ $rc != 0 ]]; then
    record ng "$id: $cmd: want exit 0, got $rc ($(<"$work/err"))"
    return
  fi
  if [[ $want_decision == none ]]; then
    if [[ -z $out ]]; then
      record ok
    else
      record ng "$id: $cmd: want no output, got $out"
    fi
    return
  fi
  if [[ $(jq -s length <<<"$out" 2>/dev/null) != 1 ]]; then
    record ng "$id: $cmd: want one JSON object, got $out"
    return
  fi
  decision=$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")
  reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$out")
  if [[ $decision == "$want_decision" && $reason == *"$want_reason"* ]]; then
    record ok
  else
    record ng "$id: $cmd: want $want_decision / *$want_reason*, got $decision / $reason"
  fi
}

check allow allow "gh api: explicit GET" 'gh api repos/o/r -X GET'
check ask ask "HTTP method override to 'DELETE'" 'gh api repos/o/r -X DELETE'
check deny deny "gh api: no explicit HTTP method" 'gh api repos/o/r'
check none none - 'echo hello'

# バイナリが無ければ判定を出さず、通常の確認に任せる。
run /usr/bin:/bin '{"tool_input":{"command":"gh api r -X GET"}}'
if [[ $rc == 0 && -z $out ]]; then
  record ok
else
  record ng "missing binary: want exit 0 and no output, got $rc / $out"
fi

# payload を待っている間のシグナルでも exit 2 (ブロック) にせず、判定を出さない。
# sh がフックを exec していなければ sh が受けて 128+n になるので、settings.json の
# コマンドそのものへ送る。
mkfifo "$work/fifo"
PATH="$work/bin:$PATH" /bin/sh -c "$HOOK_COMMAND" <"$work/fifo" >"$work/out" 2>/dev/null &
hook_pid=$!
exec 9>"$work/fifo"
sleep 0.3
kill -TERM "$hook_pid"
rc=0
wait "$hook_pid" || rc=$?
exec 9>&-
out=$(<"$work/out")
if [[ $rc == 0 && -z $out ]]; then
  record ok
else
  record ng "SIGTERM while reading: want exit 0 and no output, got $rc / $out"
fi

printf '=== gh-api-guard hook: %s cases, %s failures ===\n' "$((pass + fail))" "$fail"
[[ $fail -eq 0 ]]
