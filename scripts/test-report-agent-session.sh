#!/usr/bin/env bash
# Exercise .config/herdr/hooks/report-agent-session.sh as the hooks run it: the
# real entry point launching a freshly built binary, with a PATH that has no
# Deno on it. The report conditions themselves are covered by go test.
set -eEuo pipefail
trap 'printf "line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

repo_root=$(git rev-parse --show-toplevel)
hook="$repo_root/.config/herdr/hooks/report-agent-session.sh"
bash_bin=$(command -v bash)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/empty" "$test_dir/failing"

(cd "$repo_root/tools/report-agent-session" && go build -o "$test_dir/bin/report-agent-session" .)

# The binary hands herdr only HERDR_SOCKET_PATH, so the mock cannot find its
# interpreter or record file through the environment; both are baked in.
record="$test_dir/record"
cat >"$test_dir/herdr" <<EOF
#!$bash_bin
printf '%s\0' "\$@" >"$record"
EOF
chmod +x "$test_dir/herdr"

cat >"$test_dir/failing/report-agent-session" <<EOF
#!$bash_bin
exit 3
EOF
chmod +x "$test_dir/failing/report-agent-session"

failures=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

# run_hook <name> <stdin> <env assignment>... -- <hook args>...
# Runs the hook in a clean environment and checks it exits 0 with no output.
run_hook() {
  local name=$1 input=$2
  shift 2
  local env=()
  while [[ $1 != -- ]]; do
    env+=("$1")
    shift
  done
  shift
  rm -f -- "$record"
  local out status=0
  out=$(env -i "${env[@]}" "$bash_bin" "$hook" "$@" <<<"$input" 2>&1) || status=$?
  [[ $status -eq 0 ]] || fail "$name: exit $status"
  [[ -z $out ]] || fail "$name: unexpected output: $out"
}

herdr_env=(
  HERDR_ENV=1
  HERDR_PANE_ID=p1
  HERDR_SOCKET_PATH="$test_dir/socket"
  HERDR_BIN_PATH="$test_dir/herdr"
  PATH="$test_dir/bin"
)

# expect_report <name> <expected arg>...
# Compares the recorded argv, with --seq checked for shape instead of value.
expect_report() {
  local name=$1
  shift
  if [[ ! -f $record ]]; then
    fail "$name: herdr was not called"
    return
  fi
  local got=()
  mapfile -d '' got <"$record"
  if [[ ${got[7]:-} != --seq || ! ${got[8]:-} =~ ^[0-9]{19}$ ]]; then
    fail "$name: --seq is not epoch nanoseconds: ${got[*]}"
    return
  fi
  got[8]=SEQ
  if [[ ${got[*]@Q} != "${*@Q}" ]]; then
    fail "$name: args differ"$'\n'"   got ${got[*]@Q}"$'\n'"  want ${*@Q}"
  fi
}

expect_no_report() {
  [[ ! -f $record ]] || fail "$1: herdr was called"
}

claude_payload='{"session_id":"s 1","hook_event_name":"SessionStart","transcript_path":"/t.jsonl","source":"startup"}'
codex_payload='{"session_id":"s2","hook_event_name":"SessionStart","transcript_path":"/r.jsonl","source":"resume"}'

run_hook claude "$claude_payload" "${herdr_env[@]}" -- session claude
expect_report claude pane report-agent-session p1 --source herdr:claude --agent claude \
  --seq SEQ --agent-session-id "s 1" --agent-session-path /t.jsonl --session-start-source startup

run_hook codex "$codex_payload" "${herdr_env[@]}" -- session codex
expect_report codex pane report-agent-session p1 --source herdr:codex --agent codex \
  --seq SEQ --agent-session-id s2 --session-start-source resume

run_hook "herdr from PATH" "$claude_payload" "${herdr_env[@]}" HERDR_BIN_PATH= PATH="$test_dir/bin:$test_dir" -- session claude
expect_report "herdr from PATH" pane report-agent-session p1 --source herdr:claude --agent claude \
  --seq SEQ --agent-session-id "s 1" --agent-session-path /t.jsonl --session-start-source startup

run_hook "wrong action" "$claude_payload" "${herdr_env[@]}" -- start claude
expect_no_report "wrong action"

run_hook "wrong agent" "$claude_payload" "${herdr_env[@]}" -- session gemini
expect_no_report "wrong agent"

run_hook "outside Herdr" "$claude_payload" "${herdr_env[@]}" HERDR_ENV= -- session claude
expect_no_report "outside Herdr"

run_hook "herdr missing" "$claude_payload" "${herdr_env[@]}" HERDR_BIN_PATH="$test_dir/missing" -- session claude
expect_no_report "herdr missing"

run_hook "binary missing" "$claude_payload" "${herdr_env[@]}" PATH="$test_dir/empty" -- session claude
expect_no_report "binary missing"

run_hook "binary fails" "$claude_payload" "${herdr_env[@]}" PATH="$test_dir/failing" -- session claude
expect_no_report "binary fails"

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
echo "report-agent-session: all checks passed"
