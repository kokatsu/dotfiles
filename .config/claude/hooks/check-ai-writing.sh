#!/usr/bin/env bash
# PostToolUse hook shared by Claude Code and Codex. It lints the Markdown and
# HTML files a file tool wrote: Claude Code's Edit/Write/MultiEdit pass
# tool_input.file_path, Codex's apply_patch passes the patch in
# tool_input.command.

set -uo pipefail

payload=$(cat || true)
# codex.nix symlinks this script into ~/.config/codex/ as well, so resolving the
# config relative to $0 would miss it. Point at where it is deployed.
textlint_config="${XDG_CONFIG_HOME:-$HOME/.config}/claude/hooks/textlint-response.json"

if ! paths=$(printf '%s' "$payload" | jq -r '
  if .tool_input.file_path then .tool_input.file_path
  elif .tool_name == "apply_patch" then
    .tool_input.command // "" | split("\n")[]
    | capture("^\\s*\\*\\*\\* (Add File|Update File|Move to): (?<path>.*\\S)").path?
  else empty end' 2>/dev/null); then
  jq -n --arg message "AI 文体検査の hook 入力が不正な JSON でした。検査をスキップします。" '{systemMessage: $message}'
  exit 0
fi
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty')

files=()
while IFS= read -r file_path; do
  case "$file_path" in
  *.md | *.markdown | *.html | *.htm) ;;
  *) continue ;;
  esac
  case "$file_path" in
  /*) ;;
  *) file_path="$cwd/$file_path" ;;
  esac
  # An Update File followed by Move to names a path that no longer exists.
  [ -f "$file_path" ] && files+=("$file_path")
done <<<"$paths"

[ "${#files[@]}" -gt 0 ] || exit 0

# textlint takes about 2.5 seconds to start, so a multi-file patch is linted in
# one process to stay within the hook timeout.
if lint_output=$(
  textlint \
    --config "$textlint_config" \
    --format compact \
    --no-color \
    -- "${files[@]}" 2>&1
); then
  exit 0
else
  lint_status=$?
fi

# textlint returns 1 both for lint findings and for a config it cannot load, so
# the exit code alone cannot tell them apart. Findings always carry the
# compact formatter's ": line N, col N, " position, which no failure message
# does; the path before it is normalized by textlint, so it cannot be matched
# against the input. Anything else must not trap the agent in a rewrite loop,
# but has to surface so the check is not silently skipped.
if ! printf '%s\n' "$lint_output" | grep -Eq ': line [0-9]+, col [0-9]+, '; then
  message="AI 文体検査を実行できませんでした (textlint の終了コード: ${lint_status}、設定: ${textlint_config})
$lint_output"
  jq -n --arg message "$message" '{systemMessage: $message}'
  exit 0
fi

reason="書き込んだファイルに AI 文体のパターンが検出されました。書き込み自体は完了しています。指摘された行だけを自然で簡潔な文章に直してください。指摘箇所以外の内容は変更しないでください。

$lint_output"
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
