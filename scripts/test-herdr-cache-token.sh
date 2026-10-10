#!/usr/bin/env bash
# Exercise .config/claude/hooks/herdr-cache-token.sh as the hooks run it: the
# real entry point launching a freshly built binary, with a PATH that has no
# Deno on it. Selection and state transitions are covered by go test.
set -eEuo pipefail
trap 'printf "line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

repo_root=$(git rev-parse --show-toplevel)
hook="$repo_root/.config/claude/hooks/herdr-cache-token.sh"
bash_bin=$(command -v bash)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/herdr-only" "$test_dir/failing" "$test_dir/home/.config/claude/projects"

(cd "$repo_root/tools/herdr-cache-token" && go build -o "$test_dir/bin/herdr-cache-token" .)

# Both the binary and the fallback hand herdr only HERDR_SOCKET_PATH, so the mock
# cannot find its interpreter or record files through the environment; both are
# baked in. LEAK is set for every hook run and must not reach herdr.
record="$test_dir/record"
cat >"$test_dir/herdr" <<EOF
#!$bash_bin
printf '%s\0' "\$@" >"$record"
printf '%s|%s' "\${HERDR_SOCKET_PATH-unset}" "\${LEAK-unset}" >"$record.env"
echo "herdr stdout"
echo "herdr stderr" >&2
EOF
chmod +x "$test_dir/herdr"
ln -s "$test_dir/herdr" "$test_dir/herdr-only/herdr"

cat >"$test_dir/failing/herdr-cache-token" <<EOF
#!$bash_bin
exit 3
EOF
chmod +x "$test_dir/failing/herdr-cache-token"

# /usr/bin and /bin provide env for the fallback; Deno must not be among them.
system_path=/usr/bin:/bin
if PATH=$system_path command -v deno >/dev/null 2>&1; then
  echo "deno is on $system_path; the test cannot prove the hook runs without it" >&2
  exit 1
fi

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
  rm -f -- "$record" "$record.env"
  local out status=0
  out=$(env -i "${env[@]}" "$bash_bin" "$hook" "$@" <<<"$input" 2>&1) || status=$?
  [[ $status -eq 0 ]] || fail "$name: exit $status"
  [[ -z $out ]] || fail "$name: unexpected output: $out"
}

herdr_env=(
  HOME="$test_dir/home"
  HERDR_ENV=1
  HERDR_PANE_ID=p1
  HERDR_SOCKET_PATH="$test_dir/socket"
  HERDR_BIN_PATH="$test_dir/herdr"
  PATH="$test_dir/bin:$system_path"
  LEAK=1
)

# expect_report <name> <expected arg>...
# Compares the recorded argv. SEQ stands for 19-digit epoch nanoseconds and TTL
# for a positive millisecond count.
expect_report() {
  local name=$1
  shift
  if [[ ! -f $record ]]; then
    fail "$name: herdr was not called"
    return
  fi
  local got=() i
  mapfile -d '' got <"$record"
  local want=("$@")
  for i in "${!want[@]}"; do
    case ${want[i]} in
    SEQ) [[ ${got[i]:-} =~ ^[0-9]{19}$ ]] && got[i]=SEQ ;;
    TTL) [[ ${got[i]:-} =~ ^[1-9][0-9]*$ ]] && got[i]=TTL ;;
    esac
  done
  if [[ ${got[*]@Q} != "${want[*]@Q}" ]]; then
    fail "$name: args differ"$'\n'"   got ${got[*]@Q}"$'\n'"  want ${want[*]@Q}"
  fi
  local env_seen
  env_seen=$(<"$record.env")
  [[ $env_seen == "$test_dir/socket|unset" ]] || fail "$name: herdr environment: $env_seen"
}

expect_no_report() {
  [[ ! -f $record ]] || fail "$1: herdr was called"
}

# fmt_epoch <epoch> <date args>... formats one instant with BSD or GNU date.
fmt_epoch() {
  local epoch=$1
  shift
  date -r "$epoch" "$@" 2>/dev/null || date -d "@$epoch" "$@"
}
epoch=$(date +%s)
now=$(fmt_epoch "$epoch" -u +%Y-%m-%dT%H:%M:%SZ)
transcript="$test_dir/home/.config/claude/projects/t.jsonl"
cat >"$transcript" <<EOF
{"type":"user","sessionId":"s1","timestamp":"$now"}
{"type":"assistant","sessionId":"s1","timestamp":"$now","message":{"id":"m1","stop_reason":"end_turn","usage":{"input_tokens":5,"cache_creation_input_tokens":10,"cache_creation":{"ephemeral_5m_input_tokens":10}}}}
EOF
label="~$(fmt_epoch $((epoch + 300)) +%H:%M)"
payload="{\"session_id\":\"s1\",\"source\":\"resume\",\"transcript_path\":\"$transcript\"}"
clear_args=(pane report-metadata p1 --source claude-cache --seq SEQ --clear-token cache)
fallback_args=(pane report-metadata p1 --source claude-cache --clear-token cache)

run_hook "session publishes" "$payload" "${herdr_env[@]}" -- session
expect_report "session publishes" pane report-metadata p1 --source claude-cache --seq SEQ \
  --token "cache=$label" --ttl-ms TTL
state="$test_dir/home/.local/state/herdr-cache-token/p1-s1.json"
[[ $(<"$state") == '{"cursor_mid":"m1"}' ]] || fail "session publishes: state $(<"$state")"

run_hook "herdr from PATH" "$payload" "${herdr_env[@]}" HERDR_BIN_PATH= PATH="$test_dir/bin:$test_dir/herdr-only:$system_path" -- compact
expect_report "herdr from PATH" "${clear_args[@]}"

run_hook "default action is stop" '{"session_id":"s1","transcript_path":"/nonexistent"}' "${herdr_env[@]}" --
expect_report "default action is stop" "${clear_args[@]}"

run_hook "unknown action" "$payload" "${herdr_env[@]}" -- bogus
expect_no_report "unknown action"

run_hook "outside Herdr" "$payload" "${herdr_env[@]}" HERDR_ENV= -- compact
expect_no_report "outside Herdr"

run_hook "herdr missing" "$payload" "${herdr_env[@]}" HERDR_BIN_PATH="$test_dir/missing" -- compact
expect_no_report "herdr missing"

run_hook "binary missing" "$payload" "${herdr_env[@]}" PATH="$system_path" -- session
expect_report "binary missing" "${fallback_args[@]}"

run_hook "binary fails" "$payload" "${herdr_env[@]}" PATH="$test_dir/failing:$system_path" -- session
expect_report "binary fails" "${fallback_args[@]}"

if ((failures > 0)); then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
echo "herdr-cache-token: all checks passed"
