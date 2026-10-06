#!/usr/bin/env bash
set -eEuo pipefail
trap 'printf "line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

repo_root=$(git rev-parse --show-toplevel)
scripts="$repo_root/.config/herdr/scripts"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
export TEST_DIR="$test_dir"
export HERDR_BIN_PATH="$test_dir/bin/herdr"
unset HERDR_ACTIVE_PANE_CWD

# 各ケースが handler.sh に `respond` を定義し、引数全体 ("$*") ごとの応答を返す。
# 呼び出しはすべて calls.jsonl に記録し、notification show は応答なしで成功させる
cat >"$test_dir/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >>"$TEST_DIR/calls.jsonl"
[[ "$1 $2" == "notification show" ]] && exit 0
# shellcheck source=/dev/null
source "$TEST_DIR/handler.sh"
respond "$*"
EOF
chmod +x "$test_dir/bin/herdr"

split() { printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "$1"; }
# move <新しい pane_id> <移動先 tab_id> [作成されたタブ]
moved() {
  jq -cn --arg pane "$1" --arg tab "$2" --arg created "${3:-}" '{result: {move_result: {
    changed: true, pane: {pane_id: $pane}, target_layout: {tab_id: $tab},
    created_tab: (if $created == "" then null else {tab_id: $created} end)}}}'
}
unchanged() { printf '{"result":{"move_result":{"changed":false}}}\n'; }
export -f split moved unchanged

start_case() {
  : >"$test_dir/calls.jsonl"
  cat >"$test_dir/handler.sh"
}

# 期待する呼び出しを 1 行 1 コマンドで受け取り、記録と比べる。空白区切りでは表せない
# pane run (先頭に空白を付けて送る) と、notification show は除いて個別に確かめる
expect_calls() {
  local expected actual
  expected=$(jq -cR 'split(" ")')
  actual=$(jq -c 'select(.[0:2] != ["notification", "show"] and .[0:2] != ["pane", "run"])' \
    "$test_dir/calls.jsonl")
  if [[ "$actual" != "$expected" ]]; then
    printf '%s: unexpected calls\n--- expected\n%s\n--- actual\n%s\n' \
      "$1" "$expected" "$actual" >&2
    exit 1
  fi
}

expect_notified() {
  jq -se --arg title "$2" 'any(.[]; .[0:3] == ["notification", "show", $title])' \
    "$test_dir/calls.jsonl" >/dev/null || {
    printf '%s: missing notification %s\n' "$1" "$2" >&2
    exit 1
  }
}

expect_no_notification() {
  if jq -se 'any(.[]; .[0:2] == ["notification", "show"])' "$test_dir/calls.jsonl" >/dev/null; then
    printf '%s: unexpected notification\n' "$1" >&2
    exit 1
  fi
}

layout() {
  jq -cn --arg tab "${1:-t1}" --argjson zoomed "${2:-false}" \
    --argjson panes "$(<"$TEST_DIR/$3.json")" --argjson splits "${4:-[]}" \
    '{result: {layout: {tab_id: $tab, zoomed: $zoomed, panes: $panes, splits: $splits}}}'
}
export -f layout
cat >"$test_dir/single.json" <<'EOF'
[{"pane_id":"p1","rect":{"x":0,"y":0,"width":20}}]
EOF
cat >"$test_dir/stacked.json" <<'EOF'
[{"pane_id":"p1","rect":{"x":0,"y":0,"width":20}},{"pane_id":"p2","rect":{"x":0,"y":5,"width":20}}]
EOF

run_three() { HERDR_ACTIVE_PANE_ID=${2:-p1} bash "$scripts/three-pane-layout.sh" "$1"; }

# --- three-pane-layout.sh ---

start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false single ;;
  "pane split p1 --direction right "*) split p2 ;;
  "pane split p1 --direction down "*) split p3 ;;
  *) exit 9 ;;
  esac
}
EOF
run_three full-right
expect_calls "three: single full-right" <<'EOF'
pane layout --pane p1
pane split p1 --direction right --ratio 0.5 --no-focus
pane split p1 --direction down --ratio 0.5 --no-focus
EOF

# 同一タブ内の移動はできないので、元ペインは一時タブ経由で新しいペインの右へ戻る
start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false single ;;
  "pane split p1 --direction right "*) split p2 ;;
  "pane move p1 --new-tab --no-focus") moved p3 t9 t9 ;;
  "pane move p3 --tab t1 --target-pane p2 --split right --ratio 0.5 --focus") moved p4 t1 ;;
  "pane split p4 --direction down "*) split p5 ;;
  *) exit 9 ;;
  esac
}
EOF
run_three full-left
expect_calls "three: single full-left" <<'EOF'
pane layout --pane p1
pane split p1 --direction right --ratio 0.5 --no-focus
pane move p1 --new-tab --no-focus
pane move p3 --tab t1 --target-pane p2 --split right --ratio 0.5 --focus
pane split p4 --direction down --ratio 0.5 --no-focus
EOF

start_case <<'EOF'
respond() { layout t1 true single; }
EOF
run_three full-left
expect_calls "three: zoomed" <<<"pane layout --pane p1"
expect_notified "three: zoomed" "3ペインレイアウトを適用できません"

start_case <<'EOF'
respond() { layout t1 false stacked '[{"direction":"right"}]'; }
EOF
run_three full-left
expect_calls "three: side by side" <<<"pane layout --pane p1"
jq -se 'any(.[]; .[3] == "--body" and (.[4] | contains("左右2分割")))' \
  "$test_dir/calls.jsonl" >/dev/null

start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p2") layout t1 false stacked '[{"direction":"down"}]' ;;
  "pane move p2 --new-tab --no-focus") moved p3 t9 t9 ;;
  "pane split p1 --direction right "*) split p4 ;;
  "pane move p3 --tab t1 --target-pane p1 --split down --ratio 0.5 --focus") moved p5 t1 ;;
  *) exit 9 ;;
  esac
}
EOF
run_three full-right p2
expect_calls "three: stacked full-right" <<'EOF'
pane layout --pane p2
pane move p2 --new-tab --no-focus
pane split p1 --direction right --ratio 0.5 --no-focus
pane move p3 --tab t1 --target-pane p1 --split down --ratio 0.5 --focus
EOF

# 上ペインを元タブへ戻す移動が拒否されたら、EXIT trap が上・下ペインを元タブへ戻す
start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false stacked '[{"direction":"down"}]' ;;
  "pane move p2 --new-tab --no-focus") moved p3 t9 t9 ;;
  "pane split p1 --direction right "*) split p4 ;;
  "pane move p1 --tab t9 --target-pane p3 --split right --ratio 0.5 --focus") moved p5 t9 ;;
  "pane move p5 --tab t1 --target-pane p4 --split right --ratio 0.5 --focus") unchanged ;;
  "pane move p5 --tab t1 --target-pane p4 --split right --ratio 0.5 --no-focus") moved p6 t1 ;;
  "pane move p3 --tab t1 --target-pane p6 --split down --ratio 0.5 --no-focus") moved p7 t1 ;;
  *) exit 9 ;;
  esac
}
EOF
if run_three full-left 2>/dev/null; then
  printf 'three: rejected move unexpectedly succeeded\n' >&2
  exit 1
fi
expect_calls "three: restore after rejected move" <<'EOF'
pane layout --pane p1
pane move p2 --new-tab --no-focus
pane split p1 --direction right --ratio 0.5 --no-focus
pane move p1 --tab t9 --target-pane p3 --split right --ratio 0.5 --focus
pane move p5 --tab t1 --target-pane p4 --split right --ratio 0.5 --focus
pane move p5 --tab t1 --target-pane p4 --split right --ratio 0.5 --no-focus
pane move p3 --tab t1 --target-pane p6 --split down --ratio 0.5 --no-focus
EOF
expect_no_notification "three: restore after rejected move"

# 戻す移動も拒否され、どちらも一時タブに残ったら手動での復旧を通知する
start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false stacked '[{"direction":"down"}]' ;;
  "pane layout --pane "*) layout t9 false single ;;
  "pane move p2 --new-tab --no-focus") moved p3 t9 t9 ;;
  "pane split p1 --direction right "*) split p4 ;;
  "pane move p1 --tab t9 "*) moved p5 t9 ;;
  "pane move "*) unchanged ;;
  *) exit 9 ;;
  esac
}
EOF
if run_three full-left 2>/dev/null; then
  printf 'three: failed restore unexpectedly succeeded\n' >&2
  exit 1
fi
expect_notified "three: failed restore" "ペインを元のタブへ戻せませんでした"
jq -se 'any(.[]; . == ("pane move p3 --tab t1 --target-pane p4 --split down --ratio 0.5 --no-focus" | split(" ")))' \
  "$test_dir/calls.jsonl" >/dev/null

# --- four-pane-layout.sh ---

run_four() { HERDR_ACTIVE_PANE_ID=p1 bash "$scripts/four-pane-layout.sh"; }

start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false single ;;
  "pane split p1 --direction right "*) split p2 ;;
  "pane split "*) split px ;;
  *) exit 9 ;;
  esac
}
EOF
run_four
expect_calls "four: single" <<'EOF'
pane layout --pane p1
pane split p1 --direction right --ratio 0.5 --no-focus
pane split p1 --direction down --ratio 0.75 --no-focus
pane split p2 --direction down --ratio 0.5 --no-focus
EOF

cat >"$test_dir/four.json" <<'EOF'
[{"pane_id":"p1","rect":{"x":0,"y":0,"width":10}},{"pane_id":"p2","rect":{"x":0,"y":5,"width":10}},{"pane_id":"p3","rect":{"x":10,"y":0,"width":10}},{"pane_id":"p4","rect":{"x":10,"y":5,"width":10}}]
EOF
cat >"$test_dir/shell.json" <<'EOF'
{"result":{"process_info":{"shell_pid":1,"foreground_processes":[{"pid":1,"name":"zsh"}]}}}
EOF
cat >"$test_dir/codex.json" <<'EOF'
{"result":{"process_info":{"shell_pid":1,"foreground_processes":[{"pid":2,"name":"codex"}]}}}
EOF

# 右上は素のシェルなので claude を起動し、右下は codex が動いているので触らない
start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false four ;;
  "pane process-info --pane p3") cat "$TEST_DIR/shell.json" ;;
  "pane process-info --pane p4") cat "$TEST_DIR/codex.json" ;;
  "pane run p3  claude") ;;
  *) exit 9 ;;
  esac
}
EOF
run_four
expect_calls "four: start missing agent" <<'EOF'
pane layout --pane p1
pane process-info --pane p3
pane process-info --pane p4
EOF
jq -se 'any(.[]; . == ["pane", "run", "p3", " claude"])' "$test_dir/calls.jsonl" >/dev/null

# 右上の判定に失敗しても、右下の codex 起動は続ける
start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false four ;;
  "pane process-info --pane p3") exit 1 ;;
  "pane process-info --pane p4") cat "$TEST_DIR/shell.json" ;;
  "pane run p4  codex") ;;
  *) exit 9 ;;
  esac
}
EOF
run_four
expect_notified "four: process-info failure" "claude の起動判定に失敗しました"
jq -se 'any(.[]; . == ["pane", "run", "p4", " codex"])' "$test_dir/calls.jsonl" >/dev/null

start_case <<'EOF'
respond() { layout t1 false stacked; }
EOF
run_four
expect_calls "four: unsupported" <<<"pane layout --pane p1"
expect_notified "four: unsupported" "4ペインレイアウトを適用できません"

# --- close-pane-confirm.sh ---

run_close() { HERDR_ACTIVE_PANE_ID=p1 bash "$scripts/close-pane-confirm.sh"; }

start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") printf '{"result":{"pane":{"agent_status":"idle"}}}\n' ;;
  "pane close p1") ;;
  *) exit 9 ;;
  esac
}
EOF
run_close
expect_calls "close: idle" <<'EOF'
pane get p1
pane close p1
EOF

start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") printf '{"result":{"pane":{"agent_status":"working","terminal_title_stripped":"t"}}}\n' ;;
  "plugin pane open "*) ;;
  *) exit 9 ;;
  esac
}
EOF
run_close
jq -se 'last | .[0:3] == ["plugin", "pane", "open"] and index("TARGET_STATUS=working") != null' \
  "$test_dir/calls.jsonl" >/dev/null

start_case <<'EOF'
respond() { exit 1; }
EOF
if run_close; then
  printf 'close: failed pane get unexpectedly succeeded\n' >&2
  exit 1
fi
expect_calls "close: pane get failure" <<<"pane get p1"
expect_notified "close: pane get failure" "ペイン情報の取得に失敗しました"

printf 'herdr script tests passed\n'
