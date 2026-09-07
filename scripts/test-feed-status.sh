#!/usr/bin/env bash
set -euo pipefail

# These scripts run on Linux/WSL; macOS does not provide util-linux flock.
if [[ $(uname -s) != Linux ]]; then
  echo 'Skipping Linux feed state tests'
  exit 0
fi
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
bg_pids=()
cleanup() {
  local pid
  for pid in "${bg_pids[@]}"; do
    kill -- "-$pid" 2>/dev/null || true
  done
  for pid in "${bg_pids[@]}"; do wait "$pid" 2>/dev/null || true; done
  rm -rf "$test_dir"
}
# Each worker has its own process group, including mock grandchildren.
start_bg() {
  setsid timeout --foreground --kill-after=1 30 "$@" &
  bg_pids+=("$!")
  worker_pid=$!
}
wait_file() {
  local i
  for ((i = 0; i < 1500; i++)); do
    [[ ! -e "$1" ]] || return 0
    sleep 0.02
  done
  echo "Timed out waiting for test marker: $1" >&2
  return 1
}
trap cleanup EXIT
export FEED_WATCH_STATUS_DIR="$test_dir/state"
export FEED_WATCH_OPML_DIR="$test_dir/opml"
export FEED_TEST_DIR="$test_dir"
mkdir -p "$FEED_WATCH_STATUS_DIR" "$FEED_WATCH_OPML_DIR" "$test_dir/bin"
export STATUS_FILE="$FEED_WATCH_STATUS_DIR/status.json"
# shellcheck source=scripts/feed-status.sh
source "$repo_root/scripts/feed-status.sh"
export -f feed_status_update feed_status_read feed_lock feed_status_validate feed_status_publish wait_file
cat >"$STATUS_FILE" <<'JSON'
{"feeds":{"demo":{"last_seen_id":"old","unread_count":5,"last_summarized_id":"old-summary","type":"github","url":"https://github.com/example/demo","category":"test"},"removed":{"unread_count":4}},"extra":"keep"}
JSON
cat >"$FEED_WATCH_OPML_DIR/feeds.opml" <<'XML'
<opml><body>
<outline text="test">
<outline text="demo" xmlUrl="https://github.com/example/demo/commits.atom" htmlUrl="https://github.com/example/demo"/>
</outline>
</body></opml>
XML
cat >"$test_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -e /proc/$$/fd/8 && ! -e /proc/$$/fd/9 ]] || exit 99
printf 'fetch\n' >>"$FEED_TEST_DIR/fetch-calls"
if [[ -e "$FEED_TEST_DIR/fail-fetch" ]]; then exit 1; fi
if [[ -e "$FEED_TEST_DIR/pause-fetch" ]]; then
  touch "$FEED_TEST_DIR/fetch-ready"
  wait_file "$FEED_TEST_DIR/release"
fi
printf 'new\nold\n'
MOCK
chmod +x "$test_dir/bin/gh"
export PATH="$test_dir/bin:$PATH"
touch "$test_dir/pause-fetch"
start_bg bash "$repo_root/bin/feed-watch" check
check_pid=$worker_pid
wait_file "$test_dir/fetch-ready"
# A second check must wait for the outer lock without starting another fetch.
if FEED_WATCH_LOCK_TIMEOUT=0.1 bash "$repo_root/bin/feed-watch" check 2>"$test_dir/check-timeout"; then exit 1; fi
grep -Fq 'Failed to acquire feed lock' "$test_dir/check-timeout"
[[ $(wc -l <"$test_dir/fetch-calls") -eq 1 ]]
# Both writers must finish while the network request is still pending.
bash "$repo_root/bin/feed-watch" read --all
feed_status_update feed_status_mark_summarized demo new-summary
jq -e '.feeds.demo.unread_count == 0' "$STATUS_FILE" >/dev/null
touch "$test_dir/release"
wait "$check_pid"
check_pid=
rm "$test_dir/pause-fetch"
jq -e '.feeds.demo.unread_count == 1 and .feeds.demo.last_summarized_id == "new-summary" and .feeds.removed == null and .extra == "keep"' "$STATUS_FILE" >/dev/null

# Rechecking the same IDs must not double-count new entries.
bash "$repo_root/bin/feed-watch" check
jq -e '.feeds.demo.unread_count == 1' "$STATUS_FILE" >/dev/null
# Failed fetches must not prune a configured feed.
touch "$test_dir/fail-fetch"
bash "$repo_root/bin/feed-watch" check
jq -e '.feeds.demo.unread_count == 1' "$STATUS_FILE" >/dev/null
cp "$STATUS_FILE" "$test_dir/before"
: >"$FEED_WATCH_OPML_DIR/feeds.opml"
if bash "$repo_root/bin/feed-watch" check; then exit 1; fi
cmp "$STATUS_FILE" "$test_dir/before"
# A late summary completion must not recreate a deleted feed.
feed_status_update feed_status_mark_summarized removed ignored
jq -e '.feeds.removed == null' "$STATUS_FILE" >/dev/null

# Failed/malformed transformations must leave the published file untouched.
fail_update() {
  printf '{}\n'
  return 23
}
invalid_update() { printf 'invalid\n'; }
cp "$STATUS_FILE" "$test_dir/before"
if feed_status_update fail_update; then exit 1; fi
cmp "$STATUS_FILE" "$test_dir/before"
if feed_status_update invalid_update; then exit 1; fi
cmp "$STATUS_FILE" "$test_dir/before"

# Independent processes must not lose each other's updates.
increment() { jq '.counter = ((.counter // 0) + 1)' <<<"$1"; }
export -f increment
pids=()
for ((i = 0; i < 20; i++)); do
  start_bg bash -c 'feed_status_update increment'
  pids+=("$worker_pid")
done
for pid in "${pids[@]}"; do wait "$pid"; done
jq -e '.counter == 20' "$STATUS_FILE" >/dev/null
bash "$repo_root/bin/feed-watch" read demo
jq -e '.feeds.demo.unread_count == 0 and .counter == 20' "$STATUS_FILE" >/dev/null
# Readers must continue seeing the old complete JSON while a write is unfinished.
slow_update() {
  printf '{"feeds":'
  touch "$FEED_TEST_DIR/write-ready"
  wait_file "$FEED_TEST_DIR/release"
  printf '{}}\n'
}
cp "$STATUS_FILE" "$test_dir/before"
rm "$test_dir/release"
export -f slow_update
start_bg bash -c 'feed_status_update slow_update'
check_pid=$worker_pid
wait_file "$test_dir/write-ready"
cmp "$STATUS_FILE" "$test_dir/before"
touch "$test_dir/release"
wait "$check_pid"
check_pid=
jq -e '.feeds == {}' "$STATUS_FILE" >/dev/null
printf 'Feed state tests passed\n'

# Exercise feed-summarize itself: a state update during Claude's response must survive.
export FEED_TEST_ROOT="$repo_root"
export XDG_DATA_HOME="$test_dir/data"
cat >"$STATUS_FILE" <<'JSON'
{"feeds":{"Recent Commits to docs:main":{"last_seen_id":"new","last_summarized_id":"old","unread_count":5,"type":"github","url":"https://github.com/example/demo","category":"test"}}}
JSON
cat >"$test_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *per_page*) printf 'new\nold\n' ;;
  */pulls*) printf '[]\n' ;;
  *) printf '{"sha":"new","date":"2026-09-07","message":"fixture"}\n' ;;
esac
MOCK
cat >"$test_dir/bin/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -e /proc/$$/fd/8 && ! -e /proc/$$/fd/9 ]] || exit 99
cat >/dev/null
touch "$FEED_TEST_DIR/summary-ready"
wait_file "$FEED_TEST_DIR/summary-release"
export STATUS_FILE="$FEED_WATCH_STATUS_DIR/status.json"
# shellcheck source=scripts/feed-status.sh
source "$FEED_TEST_ROOT/scripts/feed-status.sh"
advance() {
  jq '.feeds["Recent Commits to docs:main"].last_seen_id = "newest"' <<<"$1"
}
feed_status_update advance
bash "$FEED_TEST_ROOT/bin/feed-watch" read --all
printf 'Fixture summary\n'
MOCK
cat >"$test_dir/bin/agent-browser" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FEED_TEST_DIR/browser-calls"
exit 0
MOCK
chmod +x "$test_dir/bin/claude" "$test_dir/bin/agent-browser"
start_bg bash "$repo_root/bin/feed-summarize" test
summary_pid=$worker_pid
wait_file "$test_dir/summary-ready"
[[ ! -e "$test_dir/browser-calls" ]]
if FEED_WATCH_LOCK_TIMEOUT=0.1 bash "$repo_root/bin/feed-summarize" test 2>"$test_dir/summary-timeout"; then exit 1; fi
grep -Fq 'Failed to acquire feed lock' "$test_dir/summary-timeout"
# A contender that never acquired the lock must not close the owner's browser.
[[ ! -e "$test_dir/browser-calls" ]]
touch "$test_dir/summary-release"
wait "$summary_pid"
# The owner still runs its cleanup exactly once on normal completion.
[[ $(cat "$test_dir/browser-calls") == close ]]
# The outer lock was released and the next run can finish normally.
# Keep last_seen_id equal to the already summarized ID to avoid another summary.
reset_seen() { jq '.feeds["Recent Commits to docs:main"].last_seen_id = "new"' <<<"$1"; }
# First verify the concurrent update survived before setting up the next run.
jq -e '.feeds["Recent Commits to docs:main"] | .last_seen_id == "newest" and .last_summarized_id == "new" and .unread_count == 0' "$STATUS_FILE" >/dev/null
printf 'Summary state integration test passed\n'

feed_status_update reset_seen
bash "$repo_root/bin/feed-summarize" test

# An invalid input reports a useful error and remains unchanged.
cp "$STATUS_FILE" "$test_dir/valid-status"
printf '{}\n' >"$STATUS_FILE"
if feed_status_update feed_status_mark_read null 2>"$test_dir/invalid-input"; then exit 1; fi
grep -Fq 'Invalid feed status (input)' "$test_dir/invalid-input"
[[ $(cat "$STATUS_FILE") == '{}' ]]
cp "$test_dir/valid-status" "$STATUS_FILE"
if feed_status_update invalid_update 2>"$test_dir/invalid-output"; then exit 1; fi
grep -Fq 'Invalid feed status (output)' "$test_dir/invalid-output"
cmp "$test_dir/valid-status" "$STATUS_FILE"

# The inner state lock also has a bounded wait.
exec 7>"$STATUS_FILE.lock"
flock -x 7
if FEED_WATCH_LOCK_TIMEOUT=0.1 feed_status_update feed_status_mark_read null 2>"$test_dir/state-timeout"; then exit 1; fi
grep -Fq 'Failed to acquire feed lock' "$test_dir/state-timeout"
exec 7>&-

# Simulate temporary Windows sharing violations, then a permanent failure.
mv() {
  local attempts=0
  [[ ! -f "$FEED_TEST_DIR/mv-attempts" ]] || read -r attempts <"$FEED_TEST_DIR/mv-attempts"
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" >"$FEED_TEST_DIR/mv-attempts"
  if ((attempts <= FEED_TEST_MV_FAILURES)); then
    echo 'Simulated sharing violation' >&2
    return 1
  fi
  command mv "$@"
}
FEED_TEST_MV_FAILURES=2
feed_status_update increment
[[ $(cat "$test_dir/mv-attempts") == 3 ]]
jq -e '.counter == 1' "$STATUS_FILE" >/dev/null
cp "$STATUS_FILE" "$test_dir/before-mv-failure"
printf '0\n' >"$test_dir/mv-attempts"
FEED_TEST_MV_FAILURES=10
if feed_status_update increment 2>"$test_dir/mv-error"; then exit 1; fi
[[ $(cat "$test_dir/mv-attempts") == 5 ]]
grep -Fq 'Failed to publish feed status after 5 attempts' "$test_dir/mv-error"
cmp "$test_dir/before-mv-failure" "$STATUS_FILE"
unset -f mv

# A long-lived descendant must not keep either lock after the parent exits.
cat >"$test_dir/bin/descendant" <<'MOCK'
#!/usr/bin/env bash
[[ ! -e /proc/$$/fd/8 && ! -e /proc/$$/fd/9 ]] || exit 99
sleep 20 >/dev/null 2>&1 &
printf '%s\n' "$!" >"$FEED_TEST_DIR/descendant-pid"
MOCK
chmod +x "$test_dir/bin/descendant"
export -f feed_run
# shellcheck disable=SC2016
start_bg bash -c 'exec 8>"$FEED_TEST_DIR/outer.lock"; flock -x 8; exec 9>"$FEED_TEST_DIR/inner.lock"; flock -x 9; feed_run descendant'
wait "$worker_pid"
wait_file "$test_dir/descendant-pid"
read -r descendant_pid <"$test_dir/descendant-pid"
kill -0 "$descendant_pid"
flock -n "$test_dir/outer.lock" true
flock -n "$test_dir/inner.lock" true
kill "$descendant_pid"
printf 'Retry, diagnostics, lock lifetime and serialization tests passed\n'
