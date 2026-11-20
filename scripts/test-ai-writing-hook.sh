#!/usr/bin/env bash
# Control-flow regression tests for the AI writing hook. textlint is stubbed
# so the branches are exercised without depending on rule behavior; the config
# itself is covered by test-textlint-response-config.sh.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
hook="$repo_root/.config/ai-writing/check-ai-writing.sh"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

stub_dir="$workdir/bin"
mkdir -p "$stub_dir"
cat >"$stub_dir/textlint" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$STUB_ARGS"
[ -n "$STUB_ERR" ] && printf '%s\n' "$STUB_ERR" >&2
[ -n "$STUB_OUT" ] && printf '%s\n' "$STUB_OUT"
exit "$STUB_EXIT"
STUB
chmod +x "$stub_dir/textlint"

xdg="$workdir/config"
args_file="$workdir/args"

run_hook() {
  : >"$args_file"
  printf '%s' "$3" | env \
    PATH="$stub_dir:$PATH" \
    XDG_CONFIG_HOME="$xdg" \
    STUB_ARGS="$args_file" \
    STUB_EXIT="$1" \
    STUB_OUT="$2" \
    STUB_ERR="${4:-}" \
    bash "$hook" "${@:5}"
}

payload() {
  jq -cn --arg p "$1" '{tool_name: "Write", tool_input: {file_path: $p}}'
}

patch_payload() {
  jq -cn --arg c "$1" --arg cwd "$workdir" \
    '{tool_name: "apply_patch", cwd: $cwd, tool_input: {command: $c}}'
}

finding() { jq -cn --arg p "$1" '[{filePath: $p, messages: [{line: 1, column: 1, message: "指摘", ruleId: "rule-id"}]}]'; }
clean() { jq -cn --arg p "$1" '[{filePath: $p, messages: []}]'; }

fail() {
  printf '%s\n' "$1" >&2
  return 1
}

expect_block() {
  local out
  out=$(run_hook "$1" "$2" "$3")
  [ "$(printf '%s' "$out" | jq -r '.decision // "none"')" = block ] ||
    fail "expected a block decision: $4"
}

expect_system_message() {
  local out
  out=$(run_hook "$1" "$2" "$3")
  [ "$(printf '%s' "$out" | jq -r '.decision // "none"')" = none ] ||
    fail "expected no block decision: $4"
  [ "$(printf '%s' "$out" | jq -r 'has("systemMessage")')" = true ] ||
    fail "expected a systemMessage: $4"
}

expect_silent() {
  local out
  out=$(run_hook "$1" "$2" "$3" "" "${@:5}")
  [ -z "$out" ] || fail "expected no output: $4"
}

md_file="$workdir/note.md"
printf 'テストです。\n' >"$md_file"
html_file="$workdir/page.html"
printf '<p>テストです。</p>\n' >"$html_file"

out=$(run_hook 1 "$(finding "$md_file")" "$(payload "$md_file")")
printf '%s' "$out" | jq -e --arg p "$md_file" '.decision == "block" and (.reason | contains($p))' >/dev/null ||
  fail "expected a block naming the file: markdown finding"

expect_silent 0 "$(clean "$md_file")" "$(payload "$md_file")" "clean markdown file"

# textlint は設定を読めない場合も終了コード 1 を返す。指摘と取り違えて空の書き直しを
# 要求しないことを確かめる。
expect_system_message 1 '
== No rules found, textlint hasn'"'"'t done anything ==' \
  "$(payload "$md_file")" "unreadable config"

expect_system_message 70 'textlint: command failed' "$(payload "$md_file")" "textlint crash"

expect_system_message 0 "" 'not json at all' "malformed payload"

run_hook 0 "$(clean "$md_file")" "$(payload "$md_file")" >/dev/null
grep -qx -- "--config" "$args_file" ||
  fail "expected textlint to be invoked with --config"
grep -qx -- "$xdg/ai-writing/textlint-response.json" "$args_file" ||
  fail "expected the config path to resolve under XDG_CONFIG_HOME"

expect_block 1 "$(finding "$html_file")" "$(payload "$html_file")" "HTML finding"
grep -qx -- "$html_file" "$args_file" ||
  fail "expected textlint to receive the HTML file path"

expect_silent 1 "$(finding "$workdir/script.sh")" "$(payload "$workdir/script.sh")" "unsupported file"
[ ! -s "$args_file" ] || fail "expected textlint not to run for an unsupported file"

# Codex の apply_patch は相対パスを cwd 基準で渡し、1 回で複数ファイルを変更できる
out=$(run_hook 1 "$(jq -cn --argjson md "$(finding "$md_file")" --argjson html "$(finding "$html_file")" '$md + $html')" "$(patch_payload '*** Begin Patch
*** Update File: note.md
@@
-a
+b
*** Delete File: gone.md
*** Update File: old.html
*** Move to: page.html
@@
-a
+b
*** Add File: script.sh
+echo
*** End Patch')")
printf '%s' "$out" | jq -e --arg md "$md_file" --arg html "$html_file" \
  '.decision == "block" and (.reason | contains($md) and contains($html))' >/dev/null ||
  fail "expected a block naming both patched files: apply_patch"
# textlint の起動は 1 回 2.5 秒ほどかかるため、hook の timeout 内に収まるよう 1 プロセスにまとめる
[ "$(grep -cx -- '--config' "$args_file")" = 1 ] ||
  fail "expected a single textlint process for the whole patch: apply_patch"
[ "$(sed -n '/^--$/,$p' "$args_file" | tail -n +2)" = "$md_file
$html_file" ] ||
  fail "expected exactly the existing supported files as arguments: apply_patch"

expect_silent 1 "$(finding "$md_file")" "$(patch_payload '*** Begin Patch
*** Delete File: note.md
*** End Patch')" "apply_patch delete"

expect_system_message 0 'not json' "$(payload "$md_file")" "invalid report on success"
expect_system_message 1 '[{"filePath":"note.md","messages":"bad"}]' "$(payload "$md_file")" "invalid messages"
expect_system_message 1 "$(clean "$md_file")" "$(payload "$md_file")" "failure without findings"
expect_system_message 70 "$(finding "$md_file")" "$(payload "$md_file")" "crash with a partial report"
expect_system_message 0 '[]' "$(payload "$md_file")" "empty report"
out=$(run_hook 1 "" "$(payload "$md_file")" 'config error: line 1, col 1, failed')
printf '%s' "$out" | jq -e '.systemMessage | contains("config error")' >/dev/null ||
  fail "expected stderr diagnostic, not a block"
out=$(run_hook 1 "$(finding "$md_file")" "$(payload "$md_file")" 'warning on stderr')
printf '%s' "$out" | jq -e '.decision == "block" and (.reason | contains("warning on stderr") | not)' >/dev/null ||
  fail "expected only structured findings in the block"
grep -qx -- json "$args_file" || fail "expected JSON formatter"

# Edit は structuredPatch が足した行だけを報告する
findings_at() {
  jq -cn --arg p "$1" '[{filePath: $p, messages: [$ARGS.positional[] | tonumber | {line: ., column: 1, message: "指摘", ruleId: "rule-id"}]}]' --args "${@:2}"
}
# $2 is the hunk's newStart, the rest are its lines.
edit_payload() {
  jq -cn --arg p "$1" --argjson start "$2" '{tool_name: "Edit", tool_input: {file_path: $p},
    tool_response: {structuredPatch: [{newStart: $start, lines: $ARGS.positional}]}}' --args -- "${@:3}"
}
printf '同じ文です。\n二行目です。\n同じ文です。\n四行目です。\n' >"$md_file"
out=$(run_hook 1 "$(findings_at "$md_file" 1 3 4)" "$(edit_payload "$md_file" 2 ' 二行目です。' '-古い文です。' '+同じ文です。' '+四行目です。')")
printf '%s' "$out" | jq -e '.decision == "block" and (.reason | contains("line 3,") and contains("line 4,") and (contains("line 1,") | not))' >/dev/null ||
  fail "expected only the added lines, not an identical line elsewhere: Edit"
expect_silent 1 "$(findings_at "$md_file" 1 2)" "$(edit_payload "$md_file" 2 ' 二行目です。' '-消した文です。')" "Edit that deletes text"
expect_block 1 "$(findings_at "$md_file" 1)" "$(jq -cn --arg p "$md_file" '{tool_name: "Edit", tool_input: {file_path: $p}}')" "Edit without a patch"
# textlint は ./ を解決したパスで報告する
out=$(run_hook 1 "$(findings_at "$md_file" 1 3)" "$(edit_payload "$workdir/./note.md" 3 '+同じ文です。')")
printf '%s' "$out" | jq -e '.decision == "block" and (.reason | contains("line 3,") and (contains("line 1,") | not))' >/dev/null ||
  fail "expected the Edit ranges to apply to an unnormalized path"

# コマンドラインからの実行は終了コードで結果を返す
run_cli() {
  : >"$args_file"
  env PATH="$stub_dir:$PATH" XDG_CONFIG_HOME="$xdg" STUB_ARGS="$args_file" \
    STUB_EXIT="$1" STUB_OUT="$2" STUB_ERR= bash "$hook" "${@:3}"
}
expect_status() {
  local status=0
  "${@:2}" >"$workdir/cli-out" 2>&1 </dev/null || status=$?
  [ "$status" = "$1" ] || fail "expected exit status $1, got $status: ${*:2}"
}
expect_status 1 run_cli 1 "$(finding "$md_file")" --files "$md_file"
grep -q "$md_file: line 1" "$workdir/cli-out" || fail "expected the finding on stdout: --files"
expect_status 0 run_cli 0 "$(clean "$md_file")" --files "$md_file"
expect_status 2 run_cli 70 'textlint: command failed' --files "$md_file"
expect_status 2 run_cli 0 '' --files
expect_status 2 run_cli 0 '' --unknown
status=0
printf '設定を、直す。\n' | run_cli 1 "$(finding stdin.md)" --stdin >"$workdir/cli-out" || status=$?
[ "$status" = 1 ] || fail "expected exit status 1: --stdin"
[ "$(sed -n '/^--$/,$p' "$args_file" | tail -n +2 | xargs basename)" = stdin.md ] ||
  fail "expected textlint to lint standard input as Markdown: --stdin"

# Stop は印より後にこのターンが足した行だけを、1 回の textlint で検査する
git_commit() {
  git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null commit -q "${@:2}"
}
repo="$workdir/repo"
git init -q "$repo"
printf '一行目です。\n二行目です。\n' >"$repo/tracked.md"
printf '違反のある文です。\n' >"$repo/reverted.md"
printf '違反のある文です。\n' >"$repo/restored.md"
printf '章です。\n' >"$repo/chapter.md"
printf 'ignored.md\n' >"$repo/.gitignore"
git -C "$repo" add .
git_commit "$repo" -m docs
# プロンプトの前に直した違反を、ターン中に書き戻す
printf '直した文です。\n' >"$repo/reverted.md"
# プロンプトの前に消した文書を、ターン中に復元する
git -C "$repo" rm -q restored.md
# 消した文書と同じ名前のディレクトリに、プロンプトの前に文書を置く
git -C "$repo" rm -q chapter.md
mkdir "$repo/chapter.md"
printf '前からの文です。\n' >"$repo/chapter.md/part.md"
printf '前からの変更です。\n' >>"$repo/tracked.md"
mkdir -p "$repo/docs"
printf '下書きです。\n' >"$repo/docs/draft.md"
printf '古い変更です。\n' >"$repo/old.md"
touch -t 202001010000 "$repo/old.md"
export XDG_RUNTIME_DIR="$workdir/run"
stop_payload() {
  jq -cn --arg cwd "${2:-$repo}" --argjson active "${1:-false}" \
    '{hook_event_name: "Stop", session_id: "s1", cwd: $cwd, stop_hook_active: $active}'
}
mark_turn() {
  jq -cn --arg cwd "$1" '{session_id: "s1", cwd: $cwd}' | (umask 022 && bash "$hook" --mark)
  sleep 1
}
expect_silent 1 "$(finding "$repo/tracked.md")" "$(stop_payload)" "Stop before any prompt was marked" --stop
mark_turn "$repo"
[ -f "$XDG_RUNTIME_DIR/ai-writing/s1.mark" ] || fail "expected --mark to record the turn"
[ -f "$XDG_RUNTIME_DIR/ai-writing/s1/files/docs/draft.md" ] || fail "expected --mark to snapshot uncommitted documents"
[ -z "$(find "$XDG_RUNTIME_DIR/ai-writing" \( -perm -g=r -o -perm -o=r \) -print)" ] ||
  fail "expected the snapshot to be readable only by the user"
printf '一行目です。\n足した行です。\n二行目です。\n前からの変更です。\n' >"$repo/tracked.md"
# cp -p などは更新時刻を保ったまま書き換える
touch -t 202001010000 "$repo/tracked.md"
printf '下書きです。\n追記です。\n' >"$repo/docs/draft.md"
printf '新しい文書です。\n' >"$repo/new.md"
git -C "$repo" checkout -q HEAD -- reverted.md restored.md
printf '前からの文です。\n足した文です。\n' >"$repo/chapter.md/part.md"
printf '無視される文書です。\n' >"$repo/ignored.md"
printf 'echo\n' >"$repo/script.sh"
out=$(run_hook 1 "$(jq -cn --argjson a "$(findings_at "$repo/tracked.md" 1 2 4)" \
  --argjson b "$(findings_at "$repo/docs/draft.md" 1 2)" --argjson c "$(findings_at "$repo/new.md" 1)" \
  --argjson d "$(findings_at "$repo/reverted.md" 1)" --argjson e "$(findings_at "$repo/restored.md" 1)" \
  --argjson f "$(findings_at "$repo/chapter.md/part.md" 1 2)" '$a + $b + $c + $d + $e + $f')" \
  "$(stop_payload)" "" --stop)
printf '%s' "$out" | jq -e --arg t "$repo/tracked.md" --arg d "$repo/docs/draft.md" --arg n "$repo/new.md" --arg r "$repo/reverted.md" --arg s "$repo/restored.md" --arg p "$repo/chapter.md/part.md" '
  .decision == "block" and (.reason |
    contains("\($t): line 2,") and (contains("\($t): line 1,") or contains("\($t): line 4,") | not) and
    contains("\($d): line 2,") and (contains("\($d): line 1,") | not) and
    contains("\($n): line 1,") and contains("\($r): line 1,") and contains("\($s): line 1,") and
    contains("\($p): line 2,") and (contains("\($p): line 1,") | not))' >/dev/null ||
  fail "expected only the lines this turn added: Stop"
[ "$(grep -cx -- '--config' "$args_file")" = 1 ] || fail "expected a single textlint process: Stop"
[ "$(sed -n '/^--$/,$p' "$args_file" | tail -n +2 | sort)" = "$repo/chapter.md/part.md
$repo/docs/draft.md
$repo/new.md
$repo/restored.md
$repo/reverted.md
$repo/tracked.md" ] || fail "expected only documents changed after the mark: Stop"
expect_silent 1 "$(finding "$repo/tracked.md")" "$(stop_payload true)" "Stop already continuing" --stop

fresh="$workdir/fresh"
git init -q "$fresh"
mark_turn "$fresh"
printf '新しい文書です。\n' >"$fresh/first.md"
out=$(run_hook 1 "$(finding "$fresh/first.md")" "$(stop_payload false "$fresh")" "" --stop)
printf '%s' "$out" | jq -e --arg f "$fresh/first.md" '.decision == "block" and (.reason | contains($f))' >/dev/null ||
  fail "expected a new document in a repository without commits: Stop"

printf 'ai-writing hook: 37 cases passed\n'
