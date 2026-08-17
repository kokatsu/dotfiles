#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
wrapper="$repo_root/.config/claude/skills/herdr-peer/scripts/herdr-peer"
tmp_base=$(cd -P "${TMPDIR:-/tmp}" && pwd)
test_dir=$(mktemp -d "$tmp_base/herdr-peer-test.XXXXXX")

cleanup() {
  case ${test_dir:-} in
  "$tmp_base"/herdr-peer-test.*)
    [[ -d $test_dir ]] && rm -rf -- "$test_dir"
    ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

session_id() {
  case $FAKE_SCENARIO in
  stable) printf '%s\n' '"stable-session"' ;;
  replaced) printf '%s\n' '"new-session"' ;;
  concurrent) printf '%s\n' '"concurrent-session"' ;;
  bootstrap)
    [[ -f $FAKE_STATE/session-created ]] && printf '%s\n' '"bootstrapped-session"' || printf 'null\n'
    ;;
  delayed-bootstrap)
    if [[ ! -f $FAKE_STATE/session-created ]]; then
      printf 'null\n'
    else
      count=0
      [[ ! -f $FAKE_STATE/get-count ]] || read -r count <"$FAKE_STATE/get-count"
      count=$((count + 1))
      printf '%s\n' "$count" >"$FAKE_STATE/get-count"
      if ((count >= 3)); then
        printf '%s\n' '"delayed-session"'
      else
        printf 'null\n'
      fi
    fi
    ;;
  no-session | uninitialized) printf 'null\n' ;;
  invalid-false) printf 'false\n' ;;
  invalid-empty) printf '%s\n' '""' ;;
  invalid-number) printf '42\n' ;;
  *) exit 70 ;;
  esac
}

agent_json() {
  local id
  id=$(session_id)
  jq -cn --argjson session_id "$id" '{
    pane_id: "peer-pane",
    tab_id: "tab-1",
    workspace_id: "workspace-1",
    agent: "codex",
    agent_status: "idle",
    cwd: "/repo",
    agent_session: {value: $session_id}
  }'
}

case "$1 $2" in
"pane current")
  jq -cn '{result: {pane: {
    pane_id: "current-pane",
    tab_id: "tab-1",
    workspace_id: "workspace-1",
    agent: "claude"
  }}}'
  ;;
"agent list")
  if [[ $FAKE_SCENARIO == replaced ]]; then
    listed_id='"old-session"'
  elif [[ $FAKE_SCENARIO == concurrent ]]; then
    listed_id=null
  else
    listed_id=$(session_id)
  fi
  jq -cn --argjson session_id "$listed_id" '{result: {agents: [{
    pane_id: "peer-pane",
    tab_id: "tab-1",
    workspace_id: "workspace-1",
    agent: "codex",
    agent_status: "idle",
    cwd: "/repo",
    agent_session: {value: $session_id}
  }]}}'
  ;;
"agent get")
  jq -cn --argjson agent "$(agent_json)" '{result: {agent: $agent}}'
  ;;
"agent prompt")
  touch "$FAKE_STATE/prompt-called"
  if [[ $FAKE_SCENARIO == bootstrap || $FAKE_SCENARIO == delayed-bootstrap ]]; then
    touch "$FAKE_STATE/session-created"
  fi
  jq -cn '{result: {status: "done"}}'
  ;;
"agent read")
  jq -cn '{result: {text: "peer output"}}'
  ;;
*)
  printf 'unexpected fake herdr command: %q %q\n' "${1:-}" "${2:-}" >&2
  exit 64
  ;;
esac
EOF
chmod +x "$test_dir/bin/herdr"

cat >"$test_dir/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_dir/bin/sleep"

run_wrapper() {
  local scenario=$1
  shift
  FAKE_SCENARIO=$scenario \
    FAKE_STATE="$test_dir" \
    HERDR_ENV=1 \
    HERDR_PANE_ID=current-pane \
    PATH="$test_dir/bin:$PATH" \
    "$wrapper" "$@"
}

resolve_output=$(run_wrapper uninitialized resolve)
jq -e '
  .agent == "codex" and
  .pane_id == "peer-pane" and
  .agent_session_id == null and
  .session_state == "uninitialized"
' <<<"$resolve_output" >/dev/null

read_output=$(run_wrapper uninitialized read)
jq -e '.result.text == "peer output"' <<<"$read_output" >/dev/null

resolve_output=$(run_wrapper concurrent resolve)
jq -e '.agent_session_id == "concurrent-session" and .session_state == "initialized"' <<<"$resolve_output" >/dev/null
read_output=$(run_wrapper concurrent read)
jq -e '.result.text == "peer output"' <<<"$read_output" >/dev/null

rm -f "$test_dir/prompt-called" "$test_dir/session-created" "$test_dir/get-count"
run_wrapper bootstrap prompt 'first prompt' >/dev/null
[[ -f $test_dir/prompt-called && -f $test_dir/session-created ]]

rm -f "$test_dir/prompt-called" "$test_dir/session-created" "$test_dir/get-count"
run_wrapper delayed-bootstrap prompt 'delayed first prompt' >/dev/null
[[ -f $test_dir/prompt-called && -f $test_dir/session-created ]]
[[ $(<"$test_dir/get-count") == 3 ]]

rm -f "$test_dir/prompt-called" "$test_dir/session-created" "$test_dir/get-count"
if run_wrapper no-session prompt 'delivered without session' >"$test_dir/no-session.out" 2>"$test_dir/no-session.err"; then
  printf 'expected missing post-prompt session id to fail\n' >&2
  exit 1
fi
grep -F 'peer prompt was delivered' "$test_dir/no-session.err" >/dev/null
grep -F 'do not retry automatically' "$test_dir/no-session.err" >/dev/null
[[ -f $test_dir/prompt-called && ! -s $test_dir/no-session.out ]]

run_wrapper stable prompt 'existing session' >/dev/null

rm -f "$test_dir/prompt-called"
if run_wrapper concurrent prompt 'must retry' >"$test_dir/concurrent.out" 2>"$test_dir/concurrent.err"; then
  printf 'expected concurrent session initialization to fail\n' >&2
  exit 1
fi
grep -F 'peer agent session initialized during resolution; retry' "$test_dir/concurrent.err" >/dev/null
[[ ! -f $test_dir/prompt-called ]]

rm -f "$test_dir/prompt-called"
if run_wrapper replaced prompt 'must fail' >"$test_dir/replaced.out" 2>"$test_dir/replaced.err"; then
  printf 'expected session replacement to fail\n' >&2
  exit 1
fi
grep -F 'peer agent session changed during resolution' "$test_dir/replaced.err" >/dev/null
[[ ! -f $test_dir/prompt-called ]]

for scenario in invalid-false invalid-empty invalid-number; do
  if run_wrapper "$scenario" resolve >"$test_dir/$scenario.out" 2>"$test_dir/$scenario.err"; then
    printf 'expected invalid session id to fail: %s\n' "$scenario" >&2
    exit 1
  fi
  grep -F 'failed to parse the peer agent session id' "$test_dir/$scenario.err" >/dev/null
done

printf 'herdr-peer session tests passed\n'
