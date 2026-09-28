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
printf '%s\n' "$@" >"$STUB_ARGS"
[ -n "$STUB_OUT" ] && printf '%s\n' "$STUB_OUT"
exit "$STUB_EXIT"
STUB
chmod +x "$stub_dir/textlint"

xdg="$workdir/config"
args_file="$workdir/args"

run_hook() {
  printf '%s' "$3" | env \
    PATH="$stub_dir:$PATH" \
    XDG_CONFIG_HOME="$xdg" \
    STUB_ARGS="$args_file" \
    STUB_EXIT="$1" \
    STUB_OUT="$2" \
    bash "$hook"
}

payload() {
  jq -cn --arg m "$1" --argjson active "${2:-false}" \
    '{last_assistant_message: $m, stop_hook_active: $active}'
}

finding='response.md: line 1, col 1, Error - 指摘 (rule-id)'

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

expect_block 1 "$finding" "$(payload 'テストです。')" "lint finding"

expect_silent 0 "" "$(payload 'テストです。')" "clean message"

# textlint は設定を読めない場合も終了コード 1 を返す。指摘と取り違えて空の書き直しを
# 要求しないことを確かめる。
expect_system_message 1 '
== No rules found, textlint hasn'"'"'t done anything ==' \
  "$(payload 'テストです。')" "unreadable config"

expect_system_message 70 'textlint: command failed' "$(payload 'テストです。')" "textlint crash"

# 書き直し後も指摘が残る場合、Stop hook の再帰を避けて打ち切る
expect_system_message 1 "$finding" "$(payload 'テストです。' true)" "second pass"

expect_system_message 0 "" 'not json at all' "malformed payload"

expect_silent 0 "" "$(payload '')" "empty message"

run_hook 0 "" "$(payload 'テストです。')" >/dev/null
grep -qx -- "--config" "$args_file" ||
  fail "expected textlint to be invoked with --config"
grep -qx -- "$xdg/claude/hooks/textlint-response.json" "$args_file" ||
  fail "expected the config path to resolve under XDG_CONFIG_HOME"

md_file="$workdir/note.md"
printf 'テストです。\n' >"$md_file"
file_payload() {
  jq -cn --arg p "$1" '{tool_name: "Write", tool_input: {file_path: $p}}'
}

out=$(run_hook 1 "$finding" "$(file_payload "$md_file")")
printf '%s' "$out" | jq -e --arg p "$md_file" '.decision == "block" and (.reason | contains($p))' >/dev/null ||
  fail "expected a block naming the file: markdown finding"

expect_silent 0 "" "$(file_payload "$md_file")" "clean markdown file"

html_file="$workdir/page.html"
printf '<p>テストです。</p>\n' >"$html_file"
expect_block 1 'response.html: line 1, col 1, Error - 指摘 (rule-id)' "$(file_payload "$html_file")" "HTML finding"
grep -qx -- "response.html" "$args_file" ||
  fail "expected an HTML file to be linted as response.html"

rm -f "$args_file"
expect_silent 1 "$finding" "$(file_payload "$workdir/script.sh")" "unsupported file"
[ ! -e "$args_file" ] || fail "expected textlint not to run for an unsupported file"

printf 'ai-writing hook: 12 cases passed\n'
