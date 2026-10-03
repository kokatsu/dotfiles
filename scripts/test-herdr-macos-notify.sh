#!/usr/bin/env bash
set -eEuo pipefail
trap 'printf "line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

repo_root=$(git rev-parse --show-toplevel)
plugin="$repo_root/.config/herdr/plugins/macos-notify"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/state"
export TEST_DIR="$test_dir"
export HERDR_BIN_PATH="$test_dir/bin/herdr"
export HERDR_SOCKET_PATH="$test_dir/test session.sock"
export HERDR_PLUGIN_STATE_DIR="$test_dir/state"
export HERDR_PANE_ID=w1:p1
export PATH="$test_dir/bin:$PATH"

cat >"$test_dir/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
"pane list") cat "$TEST_DIR/panes.json" ;;
"agent focus")
  [[ ! -f "$TEST_DIR/closed" ]] || exit 1
  jq -cn --arg pane "$3" --arg socket "$HERDR_SOCKET_PATH" \
    '{pane: $pane, socket: $socket}' >>"$TEST_DIR/focus.jsonl"
  ;;
*) exit 2 ;;
esac
EOF
cat >"$test_dir/bin/alerter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >>"$TEST_DIR/notifications.jsonl"
cat "$TEST_DIR/result.json"
EOF
cat >"$test_dir/bin/open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_DIR/open.log"
EOF
cat >"$test_dir/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_dir/bin/"*

reset_case() {
  : >"$test_dir/focus.jsonl"
  : >"$test_dir/notifications.jsonl"
  : >"$test_dir/open.log"
  printf '%s\n' '{"activationType":"contentsClicked"}' >"$test_dir/result.json"
  cat >"$test_dir/panes.json" <<'EOF'
{"result":{"panes":[
  {"pane_id":"w1:p1","tab_id":"w1:t1","focused":true,"agent_status":"working"},
  {"pane_id":"w2:p2","tab_id":"w2:t1","focused":false,"agent":"codex","agent_status":"done","terminal_title_stripped":"引用 ' と $(touch SHOULD_NOT_EXIST)","cwd":"/work/project"},
  {"pane_id":"w2:p3","tab_id":"w2:t1","focused":false,"agent":"claude","agent_status":"blocked","terminal_title_stripped":"承認待ち"}
]}}
EOF
}

reset_case
bash "$plugin/show.sh" w2:p2 'done'
jq -se --arg socket "$HERDR_SOCKET_PATH" \
  '. == [{pane: "w2:p2", socket: $socket}]' "$test_dir/focus.jsonl" >/dev/null
[[ $(cat "$test_dir/open.log") == '-b com.github.wez.wezterm' ]]
jq -se --arg group "herdr:$HERDR_SOCKET_PATH:w2:p2" \
  '.[0] | index($group) != null and index("引用 '\'' と $(touch SHOULD_NOT_EXIST)") != null' \
  "$test_dir/notifications.jsonl" >/dev/null
[[ ! -e SHOULD_NOT_EXIST ]]

reset_case
printf '%s\n' '{"activationType":"actionClicked"}' >"$test_dir/result.json"
bash "$plugin/show.sh" w2:p3 blocked
jq -e '.pane == "w2:p3"' "$test_dir/focus.jsonl" >/dev/null
jq -e 'index("入力・承認が必要です") != null' "$test_dir/notifications.jsonl" >/dev/null

for result in closed timeout none; do
  reset_case
  jq -cn --arg type "$result" '{activationType: $type}' >"$test_dir/result.json"
  bash "$plugin/show.sh" w2:p2 'done'
  [[ -s "$test_dir/notifications.jsonl" ]]
  [[ ! -s "$test_dir/focus.jsonl" && ! -s "$test_dir/open.log" ]]
done

reset_case
bash "$plugin/show.sh" w2:p2 blocked
bash "$plugin/show.sh" missing 'done'
bash "$plugin/show.sh" w1:p1 'done'
[[ ! -s "$test_dir/notifications.jsonl" ]]

reset_case
jq '.result.panes[0].tab_id = "w2:t1"' "$test_dir/panes.json" >"$test_dir/updated.json"
mv "$test_dir/updated.json" "$test_dir/panes.json"
bash "$plugin/show.sh" w2:p2 'done'
[[ ! -s "$test_dir/notifications.jsonl" ]]

reset_case
touch "$test_dir/closed"
if bash "$plugin/show.sh" w2:p2 'done'; then
  printf 'closed pane unexpectedly focused\n' >&2
  exit 1
fi
[[ ! -s "$test_dir/open.log" ]]
rm "$test_dir/closed"

# イベントの pane_id を使い、呼び出し元 HERDR_PANE_ID には移動しない。
reset_case
export HERDR_PLUGIN_EVENT_JSON='{"data":{"pane_id":"w2:p2","agent_status":"working"}}'
bash "$plugin/notify.sh"
[[ ! -s "$test_dir/notifications.jsonl" ]]
export HERDR_PLUGIN_EVENT_JSON='{"data":{"agent_status":"done"}}'
if bash "$plugin/notify.sh"; then
  printf 'missing event pane unexpectedly accepted\n' >&2
  exit 1
fi

export HERDR_PLUGIN_EVENT_JSON='{"data":{"pane_id":"w2:p2","agent_status":"done"}}'
bash "$plugin/notify.sh"
export HERDR_PLUGIN_EVENT_JSON='{"data":{"pane_id":"w2:p3","agent_status":"blocked"}}'
bash "$plugin/notify.sh"
for _ in {1..100}; do
  [[ $(wc -l <"$test_dir/open.log") -eq 2 ]] && break
  /bin/sleep 0.02
done
[[ $(wc -l <"$test_dir/open.log") -eq 2 ]]
jq -se 'map(.pane) | sort == ["w2:p2", "w2:p3"]' "$test_dir/focus.jsonl" >/dev/null
[[ ! -s "$test_dir/state/notifications.log" ]]

printf 'herdr macOS notification tests passed\n'
