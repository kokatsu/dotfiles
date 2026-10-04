#!/usr/bin/env bash
# Control-flow regression tests for the AI writing hook. textlint is stubbed
# so the branches are exercised without depending on rule behavior; the config
# itself is covered by test-textlint-response-config.sh.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
hook="$repo_root/.config/claude/hooks/check-ai-writing.sh"

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
    bash "$hook"
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
  out=$(run_hook "$1" "$2" "$3")
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
grep -qx -- "$xdg/claude/hooks/textlint-response.json" "$args_file" ||
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

printf 'ai-writing hook: 18 cases passed\n'
