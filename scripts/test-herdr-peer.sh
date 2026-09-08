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

bump() {
  local file=$FAKE_STATE/$1 count=0

  [[ ! -f $file ]] || read -r count <"$file"
  count=$((count + 1))
  printf '%s\n' "$count" >"$file"
  printf '%s\n' "$count"
}

sent_already() {
  [[ -f $FAKE_STATE/prompt-count ]]
}

session_id() {
  case $FAKE_SCENARIO in
  stable | marker-ok | marker-missing | marker-late | blocked-peer | read-fail | settle-reset | budget-spent)
    printf '%s\n' '"stable-session"'
    ;;
  replaced-after-send)
    if sent_already; then
      printf '%s\n' '"changed-session"'
    else
      printf '%s\n' '"stable-session"'
    fi
    ;;
  replaced) printf '%s\n' '"new-session"' ;;
  concurrent) printf '%s\n' '"concurrent-session"' ;;
  bootstrap)
    [[ -f $FAKE_STATE/session-created ]] && printf '%s\n' '"bootstrapped-session"' || printf 'null\n'
    ;;
  delayed-bootstrap)
    if [[ ! -f $FAKE_STATE/session-created ]]; then
      printf 'null\n'
    else
      count=$(bump get-count)
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

# Status only starts moving once the prompt is out, so the pre-send readiness guard
# still sees a peer it is allowed to talk to.
agent_status_value() {
  local count
  case $FAKE_SCENARIO in
  blocked-peer)
    sent_already && printf 'blocked\n' || printf 'idle\n'
    ;;
  marker-late)
    if sent_already; then
      count=$(bump status-count)
      # Post-answer hook keeps the peer working for a while, so the settle loop
      # cannot start counting immediately.
      ((count > 4)) && printf 'idle\n' || printf 'working\n'
    else
      printf 'idle\n'
    fi
    ;;
  settle-reset)
    if sent_already; then
      count=$(bump status-count)
      # Call 2 gives the settle loop a streak of one, call 3 knocks it back to
      # zero, and calls 4 and 5 rebuild it -- the reset path, not just a slow start.
      ((count == 3)) && printf 'working\n' || printf 'idle\n'
    else
      printf 'idle\n'
    fi
    ;;
  *) printf 'idle\n' ;;
  esac
}

agent_json() {
  local id status
  id=$(session_id)
  status=$(agent_status_value)
  jq -cn --argjson session_id "$id" --arg status "$status" '{
    pane_id: "peer-pane",
    tab_id: "tab-1",
    workspace_id: "workspace-1",
    agent: "codex",
    agent_status: $status,
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
  jq -cn --argjson session_id "$listed_id" --arg status "$(agent_status_value)" '{result: {agents: [{
    pane_id: "peer-pane",
    tab_id: "tab-1",
    workspace_id: "workspace-1",
    agent: "codex",
    agent_status: $status,
    cwd: "/repo",
    agent_session: {value: $session_id}
  }]}}'
  ;;
"agent get")
  jq -cn --argjson agent "$(agent_json)" '{result: {agent: $agent}}'
  ;;
"agent prompt")
  bump prompt-count >/dev/null
  printf '%s' "$4" >"$FAKE_STATE/prompt-text"
  printf '%s\n' "$@" >"$FAKE_STATE/prompt-argv"
  grep -oE 'HERDRPEEREND[0-9a-f]+' <<<"$4" | head -1 >"$FAKE_STATE/marker" || true
  if [[ $FAKE_SCENARIO == bootstrap || $FAKE_SCENARIO == delayed-bootstrap ]]; then
    touch "$FAKE_STATE/session-created"
  fi
  jq -cn '{result: {status: "done"}}'
  ;;
"agent read")
  marker=''
  [[ ! -s $FAKE_STATE/marker ]] || read -r marker <"$FAKE_STATE/marker"
  case $FAKE_SCENARIO in
  read-fail)
    printf 'fake read failure\n' >&2
    exit 3
    ;;
  marker-ok | settle-reset | budget-spent)
    printf '%s\n' "$marker"
    ;;
  marker-late)
    count=$(bump read-count)
    # The request is echoed into the pane with the marker mid-sentence; an anchored
    # search must not treat that as the reply.
    printf 'Finish your reply with a final line that contains only %s and nothing else.\n' "$marker"
    printf '001\n002\n003\n'
    if ((count >= 3)); then
      printf '%s\n' "$marker"
      # Output after the marker: `grep -q` would stop reading here and, under
      # pipefail, a SIGPIPE producer would look like an absent marker.
      seq 1 200000
    fi
    ;;
  *)
    jq -cn '{result: {text: "peer output"}}'
    ;;
  esac
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

# A controllable clock, kept out of "$test_dir/bin" so only the cases that ask for it
# are affected. It freezes time until FAKE_CLOCK_JUMP_AFTER calls have gone by, then
# jumps far past any deadline.
mkdir -p "$test_dir/clockbin"
cat >"$test_dir/clockbin/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

now=1700000000
count=0
[[ ! -f $FAKE_STATE/clock-count ]] || read -r count <"$FAKE_STATE/clock-count"
count=$((count + 1))
printf '%s\n' "$count" >"$FAKE_STATE/clock-count"
((count <= ${FAKE_CLOCK_JUMP_AFTER:-1})) || now=$((now + 100000))
printf '%s\n' "$now"
EOF
chmod +x "$test_dir/clockbin/date"

reset_state() {
  rm -f \
    "$test_dir/prompt-called" \
    "$test_dir/prompt-count" \
    "$test_dir/prompt-text" \
    "$test_dir/prompt-argv" \
    "$test_dir/marker" \
    "$test_dir/screen" \
    "$test_dir/read-count" \
    "$test_dir/status-count" \
    "$test_dir/clock-count" \
    "$test_dir/session-created" \
    "$test_dir/get-count"
}

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

run_wrapper_clock() {
  local scenario=$1 jump=$2
  shift 2
  FAKE_SCENARIO=$scenario \
    FAKE_STATE="$test_dir" \
    FAKE_CLOCK_JUMP_AFTER=$jump \
    HERDR_ENV=1 \
    HERDR_PANE_ID=current-pane \
    PATH="$test_dir/clockbin:$test_dir/bin:$PATH" \
    "$wrapper" "$@"
}

prompt_count() {
  local count=0
  [[ ! -f $test_dir/prompt-count ]] || read -r count <"$test_dir/prompt-count"
  printf '%s' "$count"
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

# The session-bootstrap cases use --no-marker so they keep exercising session
# semantics alone; the marker path has its own cases below.
reset_state
run_wrapper bootstrap prompt --no-marker 'first prompt' >/dev/null
[[ -f $test_dir/session-created ]]
[[ $(prompt_count) == 1 ]]

reset_state
run_wrapper delayed-bootstrap prompt --no-marker 'delayed first prompt' >/dev/null
[[ -f $test_dir/session-created ]]
[[ $(prompt_count) == 1 ]]
[[ $(<"$test_dir/get-count") == 3 ]]

reset_state
if run_wrapper no-session prompt --no-marker 'delivered without session' >"$test_dir/no-session.out" 2>"$test_dir/no-session.err"; then
  printf 'expected missing post-prompt session id to fail\n' >&2
  exit 1
fi
grep -F 'peer prompt was delivered' "$test_dir/no-session.err" >/dev/null
grep -F 'do not retry automatically' "$test_dir/no-session.err" >/dev/null
[[ $(prompt_count) == 1 ]]

reset_state
run_wrapper stable prompt --no-marker 'existing session' >/dev/null
[[ $(prompt_count) == 1 ]]

reset_state
if run_wrapper concurrent prompt 'must retry' >"$test_dir/concurrent.out" 2>"$test_dir/concurrent.err"; then
  printf 'expected concurrent session initialization to fail\n' >&2
  exit 1
fi
grep -F 'peer agent session initialized during resolution; retry' "$test_dir/concurrent.err" >/dev/null
[[ $(prompt_count) == 0 ]]

reset_state
if run_wrapper replaced prompt 'must fail' >"$test_dir/replaced.out" 2>"$test_dir/replaced.err"; then
  printf 'expected session replacement to fail\n' >&2
  exit 1
fi
grep -F 'peer agent session changed during resolution' "$test_dir/replaced.err" >/dev/null
[[ $(prompt_count) == 0 ]]

for scenario in invalid-false invalid-empty invalid-number; do
  if run_wrapper "$scenario" resolve >"$test_dir/$scenario.out" 2>"$test_dir/$scenario.err"; then
    printf 'expected invalid session id to fail: %s\n' "$scenario" >&2
    exit 1
  fi
  grep -F 'failed to parse the peer agent session id' "$test_dir/$scenario.err" >/dev/null
done

# The wrapper appends the completion instruction and reports confirmed once the peer
# echoes the marker on a line of its own.
reset_state
run_wrapper marker-ok prompt --timeout 5000 'confirmed round' >"$test_dir/marker-ok.out"
grep -qE 'HERDRPEEREND[0-9a-f]+' "$test_dir/prompt-text"
grep -qF 'Finish your reply with a final line' "$test_dir/prompt-text"
[[ $(prompt_count) == 1 ]]
tail -n 1 "$test_dir/marker-ok.out" | jq -e '
  .type == "herdr_peer_prompt" and
  .completion == "confirmed" and
  .readiness == "confirmed" and
  .full_answer_capture == "unverified" and
  (.marker | startswith("HERDRPEEREND"))
' >/dev/null

# The case the marker exists for: the send returns while the reply is still partial,
# the echoed request must not be mistaken for it, output continues past the marker,
# and the peer stays working through its post-answer hook.
reset_state
run_wrapper marker-late prompt --timeout 60000 'late marker round' >"$test_dir/marker-late.out"
[[ $(prompt_count) == 1 ]]
[[ $(<"$test_dir/read-count") -ge 3 ]]
tail -n 1 "$test_dir/marker-late.out" | jq -e '.completion == "confirmed" and .readiness == "confirmed"' >/dev/null

# A marker that never lands means delivered but unconfirmed, and must not be resent.
reset_state
if run_wrapper marker-missing prompt --timeout 1000 'never finishes' >"$test_dir/missing.out" 2>"$test_dir/missing.err"; then
  printf 'expected a missing completion marker to fail\n' >&2
  exit 1
fi
grep -F 'completion marker never appeared' "$test_dir/missing.err" >/dev/null
grep -F 'do not retry automatically' "$test_dir/missing.err" >/dev/null
[[ $(prompt_count) == 1 ]]
tail -n 1 "$test_dir/missing.out" | jq -e '.completion == "unconfirmed"' >/dev/null

# A pane that cannot be read is transient, not an absent marker, so it keeps polling
# and still ends as delivered-but-unconfirmed.
reset_state
if run_wrapper read-fail prompt --timeout 1000 'unreadable pane' >"$test_dir/read-fail.out" 2>"$test_dir/read-fail.err"; then
  printf 'expected an unreadable pane to fail\n' >&2
  exit 1
fi
grep -F 'do not retry automatically' "$test_dir/read-fail.err" >/dev/null
[[ $(prompt_count) == 1 ]]
tail -n 1 "$test_dir/read-fail.out" | jq -e '.completion == "unconfirmed"' >/dev/null

# A blocked peer is a dead end rather than something to wait out.
reset_state
if run_wrapper blocked-peer prompt --timeout 60000 'blocked peer' >"$test_dir/blocked.out" 2>"$test_dir/blocked.err"; then
  printf 'expected a blocked peer to fail\n' >&2
  exit 1
fi
grep -F 'peer is blocked' "$test_dir/blocked.err" >/dev/null
grep -F 'do not retry automatically' "$test_dir/blocked.err" >/dev/null
[[ $(prompt_count) == 1 ]]
tail -n 1 "$test_dir/blocked.out" | jq -e '.completion == "unconfirmed"' >/dev/null

# A peer replaced after delivery still owes the caller a verdict and the reminder
# that the prompt is already out; the die is buried in the identity recheck.
reset_state
if run_wrapper replaced-after-send prompt --timeout 60000 'replaced mid-poll' >"$test_dir/replaced-after.out" 2>"$test_dir/replaced-after.err"; then
  printf 'expected a peer replaced after delivery to fail\n' >&2
  exit 1
fi
grep -F 'peer agent session changed after the prompt was delivered' "$test_dir/replaced-after.err" >/dev/null
grep -F 'already delivered or its delivery is unknown' "$test_dir/replaced-after.err" >/dev/null
[[ $(prompt_count) == 1 ]]
tail -n 1 "$test_dir/replaced-after.out" | jq -e '.type == "herdr_peer_prompt" and .completion == "unconfirmed"' >/dev/null

# The settle loop must survive a peer that goes back to working after it had already
# started counting, not merely one that is slow to become idle.
reset_state
run_wrapper settle-reset prompt --timeout 60000 'settle resets' >"$test_dir/settle.out"
[[ $(prompt_count) == 1 ]]
[[ $(<"$test_dir/status-count") -ge 5 ]]
tail -n 1 "$test_dir/settle.out" | jq -e '.completion == "confirmed" and .readiness == "confirmed"' >/dev/null

# The send is handed what is left of the shared budget, not the requested amount a
# second time. The clock is frozen throughout: on the real one a second boundary
# between the deadline and the send would legitimately abort the run.
reset_state
run_wrapper_clock marker-ok 50 prompt --timeout 1 'derived budget' >/dev/null
[[ $(prompt_count) == 1 ]]
grep -qxF -- '--timeout' "$test_dir/prompt-argv"
grep -qxF -- '1000' "$test_dir/prompt-argv"

# A budget already spent during resolution stops before a new send starts. Nothing
# was delivered, so this failure must not carry the delivered warning.
reset_state
if run_wrapper_clock budget-spent 1 prompt --timeout 1000 'too late to send' >"$test_dir/spent.out" 2>"$test_dir/spent.err"; then
  printf 'expected an exhausted budget to stop before sending\n' >&2
  exit 1
fi
grep -F 'budget was spent before the prompt could be sent' "$test_dir/spent.err" >/dev/null
if grep -qF 'already delivered' "$test_dir/spent.err"; then
  printf 'unexpected delivered warning for a prompt that was never sent\n' >&2
  exit 1
fi
[[ $(prompt_count) == 0 ]]
[[ ! -s $test_dir/spent.out ]]

# --no-marker sends the prompt verbatim and never claims completion.
reset_state
run_wrapper marker-missing prompt --no-marker 'verbatim prompt' >"$test_dir/no-marker.out"
[[ $(prompt_count) == 1 ]]
[[ $(<"$test_dir/prompt-text") == 'verbatim prompt' ]]
tail -n 1 "$test_dir/no-marker.out" | jq -e '.completion == "unconfirmed" and .marker == null' >/dev/null

printf 'herdr-peer session tests passed\n'
