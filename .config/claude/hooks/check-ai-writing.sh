#!/usr/bin/env bash
# AI writing check shared by Claude Code and Codex. As a PostToolUse hook for
# file tools it lints the written Markdown or HTML file; as a Stop hook it lints
# only the latest assistant message so textlint starts once per response instead
# of scanning a transcript.

set -uo pipefail

payload=$(cat || true)
# codex.nix symlinks this script into ~/.config/codex/ as well, so resolving the
# config relative to $0 would miss it. Point at where it is deployed.
textlint_config="${XDG_CONFIG_HOME:-$HOME/.config}/claude/hooks/textlint-response.json"

if ! file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null); then
  jq -n --arg message "AI 文体検査の hook 入力が不正な JSON でした。検査をスキップします。" '{systemMessage: $message}'
  exit 0
fi

# The --stdin-filename extension selects the textlint plugin.
lint_name=response.md
if [ -n "$file_path" ]; then
  case "$file_path" in
  *.md | *.markdown) ;;
  *.html | *.htm) lint_name=response.html ;;
  *) exit 0 ;;
  esac
  text=$(cat -- "$file_path" 2>/dev/null) || exit 0
else
  text=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')
fi

[ -n "$text" ] || exit 0

if lint_output=$(
  printf '%s\n' "$text" |
    textlint \
      --config "$textlint_config" \
      --stdin \
      --stdin-filename "$lint_name" \
      --format compact \
      --no-color 2>&1
); then
  exit 0
else
  lint_status=$?
fi

# textlint returns 1 both for lint findings and for a config it cannot load, so
# the exit code alone cannot tell them apart. Findings are always prefixed with
# the --stdin-filename, which no failure message carries. Anything else must not
# trap the agent in a rewrite loop, but has to surface so the check is not
# silently skipped.
case "$lint_output" in
*"$lint_name:"*) ;;
*)
  message="AI 文体検査を実行できませんでした (textlint の終了コード: ${lint_status}、設定: ${textlint_config})
$lint_output"
  jq -n --arg message "$message" '{systemMessage: $message}'
  exit 0
  ;;
esac

if [ -n "$file_path" ]; then
  reason="${file_path} に AI 文体のパターンが検出されました。指摘された行だけを自然で簡潔な文章に直してください。指摘箇所以外の内容は変更しないでください。行番号は ${file_path} の行番号です。

$lint_output"
  jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
  exit 0
fi

# A Stop hook continuation causes another Stop event. Permit at most one rewrite
# to avoid looping on a false positive or a finding that cannot be resolved.
if printf '%s' "$payload" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then
  message="AI 文体の指摘が書き直し後も残っています:
$lint_output"
  jq -n --arg message "$message" '{systemMessage: $message}'
  exit 0
fi

reason="最終回答に AI 文体のパターンが検出されました。指摘箇所だけを自然で簡潔な文章に修正し、修正を反映した最終回答の全文を再出力してください。修正部分だけを出力してはいけません。指摘箇所以外の内容、根拠、コマンド、ファイルパス、引用は変更しないでください。

$lint_output"
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
