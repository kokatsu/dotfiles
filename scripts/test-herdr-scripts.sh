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

start_case <<'EOF'
respond() {
  case "$1" in
  "pane layout --pane p1") layout t1 false single ;;
  "pane split p1 --direction right "*) split p2 ;;
  "pane swap --source-pane p1 --target-pane p2") printf '{"result":{"swap":{"changed":true}}}\n' ;;
  "pane split p1 --direction down "*) split p3 ;;
  *) exit 9 ;;
  esac
}
EOF
run_three full-left
expect_calls "three: single full-left" <<'EOF'
pane layout --pane p1
pane split p1 --direction right --ratio 0.5 --no-focus
pane swap --source-pane p1 --target-pane p2
pane split p1 --direction down --ratio 0.5 --no-focus
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

# --- pick-agent-path.sh ---

repo="$test_dir/repo"
mkdir -p "$repo/src" "$test_dir/other" "$test_dir/claude/projects/x" "$test_dir/codex/sessions/2026/10/13"
touch "$repo/app.py" "$repo/justfile" "$repo/src/a.ts" "$repo/src/thinking.ts" "$repo/src/tool.ts" \
  "$test_dir/other/app.py"

claude_log="$test_dir/claude/projects/x/s1.jsonl"
jq -cn --arg cwd "$repo" --arg other "$test_dir/other" '
  {type: "assistant", cwd: $cwd, message: {content: [{type: "text", text: "old `app.py` and src/a.ts:12"}]}},
  {type: "user", cwd: $cwd, message: {content: [{type: "text", text: "src/thinking.ts"}]}},
  {type: "assistant", cwd: $cwd, isSidechain: true, message: {content: [{type: "text", text: "src/tool.ts"}]}},
  {type: "assistant", cwd: $cwd, message: {content: [
    {type: "thinking", thinking: "src/thinking.ts"},
    {type: "tool_use", input: {file_path: "src/tool.ts"}},
    {type: "text", text: "見て: `src/a.ts:12`、[app.py:7](\($other)/app.py:7:3)。`justfile` と src と missing.ts"}]}}
' >"$claude_log"
printf '{"type":"assistant","cwd":' >>"$claude_log"

actual=$(bash "$scripts/pick-agent-path.sh" --list claude "$claude_log")
expected=$(printf '%s\t%s\t%s\n' \
  "$test_dir/other/app.py" 7 "${test_dir/#"$HOME"/"~"}/other/app.py:7" \
  "$repo/src/a.ts" 12 "src/a.ts:12" \
  "$repo/justfile" "" "justfile" \
  "$repo/app.py" "" "app.py")
if [[ "$actual" != "$expected" ]]; then
  printf 'pick: claude list\n--- expected\n%s\n--- actual\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

codex_log="$test_dir/codex/sessions/2026/10/13/rollout-2026-10-13T00-00-00-c1.jsonl"
jq -cn --arg cwd "$repo" '
  {type: "session_meta", payload: {id: "c1", cwd: $cwd}},
  {type: "response_item", payload: {type: "message", role: "user", content: [{type: "input_text", text: "app.py"}]}},
  {type: "response_item", payload: {type: "message", role: "assistant", content: [
    {type: "output_text", text: "[a.ts:3](\($cwd)/src/a.ts:3)"}]}}
' >"$codex_log"
actual=$(bash "$scripts/pick-agent-path.sh" --list codex "$codex_log")
expected=$(printf '%s\t%s\t%s' "$repo/src/a.ts" 3 "src/a.ts:3")
if [[ "$actual" != "$expected" ]]; then
  printf 'pick: codex list\n--- expected\n%s\n--- actual\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

# 日本語を含むパスは断片 (src/) にならず、山括弧のリンク先は空白ごと取る。行範囲は先頭の行で開く
touch "$repo/src/日本語.ts" "$repo/src/My File.ts"
jq -cn --arg cwd "$repo" --arg text "\`src/日本語.ts:7\` [a.ts](<$repo/src/a.ts:5>) [My File.ts](<$repo/src/My File.ts:9>) \`app.py:3-4\`" \
  '{type: "assistant", cwd: $cwd, message: {content: [{type: "text", text: $text}]}}' >"$test_dir/jp.jsonl"
actual=$(bash "$scripts/pick-agent-path.sh" --list claude "$test_dir/jp.jsonl")
expected=$(printf '%s\t%s\t%s\n' \
  "$repo/src/a.ts" 5 "src/a.ts:5" \
  "$repo/src/My File.ts" 9 "src/My File.ts:9" \
  "$repo/src/日本語.ts" 7 "src/日本語.ts:7" \
  "$repo/app.py" 3 "app.py:3")
if [[ "$actual" != "$expected" ]]; then
  printf 'pick: non-ASCII and angle links\n--- expected\n%s\n--- actual\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

# 強調の * は前後だけ外し、グロブ (src/*.ts) は src/ の断片にしない
jq -cn --arg cwd "$repo" '{type: "assistant", cwd: $cwd, message: {content: [{type: "text",
  text: "**src/a.ts:7** と *app.py* と **src/日本語.ts**を、src/*.ts"}]}}' >"$test_dir/emphasis.jsonl"
actual=$(bash "$scripts/pick-agent-path.sh" --list claude "$test_dir/emphasis.jsonl")
expected=$(printf '%s\t%s\t%s\n' \
  "$repo/src/a.ts" 7 "src/a.ts:7" \
  "$repo/app.py" "" "app.py" \
  "$repo/src/日本語.ts" "" "src/日本語.ts")
if [[ "$actual" != "$expected" ]]; then
  printf 'pick: emphasis\n--- expected\n%s\n--- actual\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

# fzf は FZF_PICK に一致する最初の行を選び、--expect があれば FZF_KEY を押したキーとして返す。
# open-in-nvim.sh は HERDR_BIN_PATH を使わず herdr を直接呼ぶので、偽 herdr を PATH の先頭に置く
cat >"$test_dir/bin/fzf" <<'EOF'
#!/usr/bin/env bash
for a; do [[ $a == --expect* ]] && printf '%s\n' "${FZF_KEY:-}"; done
grep -m1 -E -- "${FZF_PICK:-}" || true
EOF
cat >"$test_dir/bin/xsel" <<'EOF'
#!/usr/bin/env bash
cat >"$TEST_DIR/clipboard"
EOF
cp "$test_dir/bin/xsel" "$test_dir/bin/pbcopy"
chmod +x "$test_dir/bin/fzf" "$test_dir/bin/xsel" "$test_dir/bin/pbcopy"

run_pick() {
  PATH="$test_dir/bin:$PATH" HERDR_ACTIVE_PANE_ID=p1 \
    CLAUDE_CONFIG_DIR="$test_dir/claude" CODEX_HOME="$test_dir/codex" \
    bash "$scripts/pick-agent-path.sh"
}

# 閉じる理由は通知ではなく popup に出す。stdin を閉じてキー待ちを抜ける
expect_explained() {
  local out
  out=$(run_pick </dev/null)
  if [[ "$out" != *"$2"* ]]; then
    printf '%s: missing %s\n--- actual\n%s\n' "$1" "$2" "$out" >&2
    exit 1
  fi
  expect_no_notification "$1"
}

start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") printf '{"result":{"pane":{"agent":null}}}\n' ;;
  *) exit 9 ;;
  esac
}
EOF
expect_explained "pick: no agent" "Claude Code / Codex のペインではありません"
expect_calls "pick: no agent" <<<"pane get p1"

start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") printf '{"result":{"pane":{"agent":"claude","agent_session":{"value":"gone"}}}}\n' ;;
  *) exit 9 ;;
  esac
}
EOF
expect_explained "pick: no log" "セッションの会話ログが見つかりません"
expect_calls "pick: no log" <<<"pane get p1"

jq -cn '{type: "assistant", cwd: "/", message: {content: [{type: "text", text: "パスなし"}]}}' \
  >"$test_dir/claude/projects/x/s2.jsonl"
start_case <<'EOF2'
respond() {
  case "$1" in
  "pane get p1") printf '{"result":{"pane":{"agent":"claude","agent_session":{"value":"s2"}}}}\n' ;;
  *) exit 9 ;;
  esac
}
EOF2
expect_explained "pick: no paths" "応答に実在するパスがありません"

# Codex のログは herdr の agent_session ではなく、タイトルと同じ名前のスレッドから探す。
# 名前が同じでも cwd が違うセッション (c3, c5) は候補にしない。最後に調べる c5 が
# 一致しなくても、それまでに見つけた候補で続ける
codex_sessions="$test_dir/codex/sessions/2026/10/13"
for id in c2 c3 c4 c5; do
  cwd=$repo text="\`app.py\`"
  [[ $id == c3 || $id == c5 ]] && cwd=$test_dir/other
  [[ $id == c4 ]] && text="\`justfile\`"
  jq -cn --arg id "$id" --arg cwd "$cwd" --arg text "$text" '
    {type: "session_meta", payload: {id: $id, cwd: $cwd}},
    {type: "response_item", payload: {type: "message", role: "assistant", content: [{type: "output_text", text: $text}]}}
  ' >"$codex_sessions/rollout-2026-10-13T00-00-00-$id.jsonl"
done
jq -cn '
  {id: "c1", thread_name: "old name", updated_at: "2026-10-13T00:00:00Z"},
  {id: "c1", thread_name: "Open target thread", updated_at: "2026-10-13T00:01:00Z"},
  {id: "c2", thread_name: "Dup", updated_at: "2026-10-13T00:02:00Z"},
  {id: "c3", thread_name: "Dup", updated_at: "2026-10-13T00:03:00Z"},
  {id: "c4", thread_name: "Dup", updated_at: "2026-10-13T00:04:00Z"},
  {id: "c5", thread_name: "Dup", updated_at: "2026-10-13T00:05:00Z"}
' >"$test_dir/codex/session_index.jsonl"
codex_pane() {
  jq -cn --arg title "$1" --arg cwd "$TEST_DIR/repo" \
    '{result: {pane: {agent: "codex", agent_session: {value: "stale"}, terminal_title_stripped: $title, cwd: $cwd}}}'
}
export -f codex_pane

start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") codex_pane "old name" ;;
  *) exit 9 ;;
  esac
}
EOF
expect_explained "pick: codex title from an old name" "タイトルと同じ名前の Codex のセッションが見つかりません"

# 同じ名前が 2 件残れば選ばせる。選んだ c4 のログから justfile をコピーする
start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") codex_pane "Dup" ;;
  *) exit 9 ;;
  esac
}
EOF
FZF_PICK='c4\.jsonl|justfile' FZF_KEY=ctrl-y run_pick </dev/null
[[ $(<"$test_dir/clipboard") == "$repo/justfile" ]]

# 省略されたタイトルは前方一致で探す。同じタブに nvim がないので、
# open-in-nvim.sh の 1 行目の cwd と workspace で新規タブを作る
start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") codex_pane "Open tar..." ;;
  "pane list") printf '{"result":{"panes":[{"pane_id":"p1","focused":true,"cwd":"/work","workspace_id":"w1","tab_id":"t1"}]}}\n' ;;
  "pane process-info --pane p1") printf '{"result":{"process_info":{"foreground_processes":[]}}}\n' ;;
  "tab create "*) printf '{"result":{"root_pane":{"pane_id":"p9"}}}\n' ;;
  "pane run "*) ;;
  *) exit 9 ;;
  esac
}
EOF
FZF_PICK=a.ts run_pick </dev/null
expect_calls "pick: open in new tab" <<'EOF'
pane get p1
pane list
pane process-info --pane p1
tab create --workspace w1 --cwd /work --focus
EOF
jq -se --arg file "$repo/src/a.ts" \
  'last | .[0:3] == ["pane", "run", "p9"] and (.[3] | contains("+3 ") and contains($file))' \
  "$test_dir/calls.jsonl" >/dev/null

start_case <<'EOF'
respond() {
  case "$1" in
  "pane get p1") printf '{"result":{"pane":{"agent":"claude","agent_session":{"value":"s1"}}}}\n' ;;
  *) exit 9 ;;
  esac
}
EOF
FZF_PICK=justfile FZF_KEY=ctrl-y run_pick </dev/null
expect_calls "pick: copy" <<<"pane get p1"
[[ $(<"$test_dir/clipboard") == "$repo/justfile" ]]

# --- search-target.sh ---

export REAL_FZF
REAL_FZF=$(command -v fzf)
mkdir -p "$test_dir/config/herdr"
cat >"$test_dir/config/herdr/search-colors.json" <<'EOF'
{"peach":[250,179,135],"blue":[137,180,250],"yellow":[249,226,175],"red":[243,139,168],"green":[166,227,161],"overlay1":[127,132,156],"subtext0":[166,173,200]}
EOF
cat >"$test_dir/bin/fzf" <<'EOF'
#!/usr/bin/env bash
cat >"$TEST_DIR/search-targets.tsv"
if [[ -n ${FZF_STATUS:-} ]]; then exit "$FZF_STATUS"; fi
exec "$REAL_FZF" "$@" --filter="$FZF_PICK" <"$TEST_DIR/search-targets.tsv"
EOF
# ソケット API への要求も calls.jsonl に `socket <method> <pane_id>` として記録する
cat >"$test_dir/bin/socat" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "- UNIX-CONNECT:$HERDR_SOCKET_PATH" ]] || exit 9
jq -c '["socket", .method, .params.pane_id]' >>"$TEST_DIR/calls.jsonl"
if [[ ${FOCUS_STATUS:-0} == 0 ]]; then
  printf '{"id":"search-target","result":{"type":"pane_info"}}\n'
else
  printf '{"id":"search-target","error":{"code":"pane_not_found"}}\n'
fi
EOF
chmod +x "$test_dir/bin/fzf" "$test_dir/bin/socat"

cat >"$test_dir/search-snapshot.json" <<'EOF'
{"result":{"snapshot":{
  "workspaces":[{"workspace_id":"w1","label":"開発"},{"workspace_id":"w2","label":"dotfiles"}],
  "tabs":[
    {"workspace_id":"w1","tab_id":"w1:t1","label":"[1] API","agent_status":"working"},
    {"workspace_id":"w2","tab_id":"w2:t1","label":"[1] 設定","agent_status":"idle"},
    {"workspace_id":"w2","tab_id":"w2:t2","label":"[2] シェル"}],
  "panes":[
    {"workspace_id":"w1","pane_id":"w1:p1","tab_id":"w1:t1","cwd":"/work/old","agent_status":"unknown"},
    {"workspace_id":"w1","pane_id":"w1:p2","tab_id":"w1:t1","cwd":"/work/old","foreground_cwd":"/work/日本語 project",
      "agent":"claude","agent_status":"blocked","terminal_title_stripped":"日本語の設計レビュー"},
    {"workspace_id":"w2","pane_id":"w2:p1","tab_id":"w2:t1","cwd":"/work/dotfiles","agent":"codex","agent_status":"done"},
    {"workspace_id":"w2","pane_id":"w2:p2","tab_id":"w2:t2","cwd":"/work/shell","agent_status":"unknown"},
    {"workspace_id":"w2","pane_id":"w2:p3","tab_id":"w2:t2","cwd":"/work/背景 dir","agent_status":"unknown"}],
  "agents":[]
}}}
EOF

search_handler() {
  start_case <<'EOF'
respond() {
  case "$1" in
  "api snapshot") cat "$TEST_DIR/search-snapshot.json" ;;
  "pane read "*)
    [[ ${READ_STATUS:-0} == 0 ]] || return "$READ_STATUS"
    printf 'テスト用の端末出力\n次の行\n'
    ;;
  *) exit 9 ;;
  esac
}
EOF
}
run_search() {
  HERDR_SOCKET_PATH="$test_dir/herdr.sock" XDG_CONFIG_HOME="$test_dir/config" PATH="$test_dir/bin:$PATH" \
    bash "$scripts/search-target.sh"
}

search_handler
FZF_PICK="'/work/old" run_search
expect_calls 'search: shell pane in a split tab' <<'EOF'
api snapshot
socket pane.focus w1:p1
EOF
(($(wc -l <"$test_dir/search-targets.tsv") == 5))
[[ $(cut -f1 "$test_dir/search-targets.tsv" | sort | uniq -d) == "" ]]
awk -F '\t' '$1 == "w1:p2" && $7 == "/work/日本語 project" {found=1} END {exit !found}' \
  "$test_dir/search-targets.tsv"

search_handler
FZF_PICK="'背景" run_search
expect_calls 'search: shell pane in another workspace by cwd' <<'EOF'
api snapshot
socket pane.focus w2:p3
EOF

search_handler
FZF_PICK="'blocked" run_search
expect_calls 'search: colored state remains searchable and preserves target ID' <<'EOF'
api snapshot
socket pane.focus w1:p2
EOF

search_handler
FZF_PICK="'設計レビュー" run_search
expect_calls 'search: Japanese agent title' <<'EOF'
api snapshot
socket pane.focus w1:p2
EOF

search_handler
FZF_PICK="'codex" run_search
expect_calls 'search: agent without title' <<'EOF'
api snapshot
socket pane.focus w2:p1
EOF

search_handler
preview=$(bash "$scripts/search-target.sh" --preview "$test_dir/search-snapshot.json" w1:p2)
[[ "$preview" == *'ワークスペース: 開発'* ]]
[[ "$preview" == *'タブ: [1] API'* ]]
[[ "$preview" == *'作業名: 日本語の設計レビュー'* ]]
[[ "$preview" == *'状態: claude / blocked'* ]]
[[ "$preview" == *'ディレクトリ: /work/日本語 project'* ]]
[[ "$preview" == *$'テスト用の端末出力\n次の行'* ]]
expect_calls 'search: agent preview reads without focusing' <<<'pane read w1:p2 --source recent --lines 50 --format text --raw'

search_handler
preview=$(bash "$scripts/search-target.sh" --preview "$test_dir/search-snapshot.json" w2:p3)
[[ "$preview" == *'状態: shell'* ]]
[[ "$preview" == *'ディレクトリ: /work/背景 dir'* ]]
expect_calls 'search: shell preview' <<<'pane read w2:p3 --source recent --lines 50 --format text --raw'

search_order() {
  XDG_CONFIG_HOME="$test_dir/config" bash "$scripts/search-target.sh" --list "$test_dir/search-snapshot.json" "$1" |
    cut -f1 | paste -sd ' ' -
}
[[ $(search_order default) == 'w1:p1 w1:p2 w2:p1 w2:p2 w2:p3' ]]
[[ $(search_order priority) == 'w1:p2 w2:p1 w1:p1 w2:p2 w2:p3' ]]
toggle=$(FZF_PROMPT='作業を検索> ' bash "$scripts/search-target.sh" --toggle "$test_dir/search-snapshot.json")
[[ $toggle == 'change-prompt(作業を検索 [要対応優先]> )+reload(bash '*' --list '*' priority)' ]]
toggle=$(FZF_PROMPT='作業を検索 [要対応優先]> ' bash "$scripts/search-target.sh" --toggle "$test_dir/search-snapshot.json")
[[ $toggle == 'change-prompt(作業を検索> )+reload(bash '*' --list '*' default)' ]]

search_handler
preview=$(READ_STATUS=1 bash "$scripts/search-target.sh" --preview "$test_dir/search-snapshot.json" w2:p1)
[[ "$preview" == *'端末出力を取得できませんでした'* ]]
expect_no_notification 'search: preview failure stays in preview'

for status in 1 130; do
  search_handler
  FZF_STATUS=$status run_search
  expect_calls "search: cancel $status" <<<'api snapshot'
  expect_no_notification "search: cancel $status"
done

search_handler
if FZF_STATUS=2 run_search; then exit 1; fi
expect_calls 'search: fzf failure' <<<'api snapshot'
expect_notified 'search: fzf failure' '作業検索に失敗しました'

search_handler
if FOCUS_STATUS=1 FZF_PICK="'codex" run_search; then exit 1; fi
expect_notified 'search: target closed' '選択したペインへ移動できませんでした'

# 改行や TAB を含むタイトルも 1 候補に収め、制御文字を端末へ渡さない。
jq '.result.snapshot.panes[1].terminal_title_stripped = "制御\n文字\t入り\u001bタイトル"' \
  "$test_dir/search-snapshot.json" >"$test_dir/search-control.json"
mv "$test_dir/search-control.json" "$test_dir/search-snapshot.json"
search_handler
FZF_PICK="'制御" run_search
(($(wc -l <"$test_dir/search-targets.tsv") == 5))
awk -F '\t' 'NF != 7 {exit 1}' "$test_dir/search-targets.tsv"

printf '%s\n' '{"result":{"snapshot":{"workspaces":[],"tabs":[],"agents":[],"panes":[]}}}' \
  >"$test_dir/search-snapshot.json"
search_handler
run_search
expect_calls 'search: empty session' <<<'api snapshot'
expect_notified 'search: empty session' '検索できるペインがありません'

for invalid in '{}' '{"result":{"snapshot":{"workspaces":null,"tabs":[],"agents":[],"panes":[]}}}' broken; do
  printf '%s\n' "$invalid" >"$test_dir/search-snapshot.json"
  search_handler
  if run_search 2>/dev/null; then exit 1; fi
  expect_calls 'search: invalid snapshot' <<<'api snapshot'
  expect_notified 'search: invalid snapshot' 'ペイン一覧を作成できませんでした'
done

start_case <<'EOF'
respond() { return 1; }
EOF
if run_search; then exit 1; fi
expect_calls 'search: snapshot failure' <<<'api snapshot'
expect_notified 'search: snapshot failure' 'ペイン一覧の取得に失敗しました'

printf 'herdr script tests passed\n'
