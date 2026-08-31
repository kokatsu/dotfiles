#!/usr/bin/env bash
# Stop hook shared by Claude Code and Codex. It checks only the latest assistant
# message so textlint starts once per response instead of scanning a transcript.

set -uo pipefail

payload=$(cat || true)
notify_hook=${1:-}

notify() {
  [ -n "$notify_hook" ] || return 0
  printf '%s' "$payload" | bash "$notify_hook" >/dev/null 2>&1 || true
}

if ! message=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null); then
  notify
  jq -n --arg message "AI 文体検査の hook 入力が不正な JSON でした。検査をスキップします。" '{systemMessage: $message}'
  exit 0
fi

if [ -z "$message" ]; then
  notify
  exit 0
fi

if lint_output=$(
  printf '%s\n' "$message" |
    textlint \
      --no-textlintrc \
      --preset @textlint-ja/ai-writing \
      --stdin \
      --stdin-filename response.md \
      --format compact \
      --no-color 2>&1
); then
  notify
  exit 0
else
  lint_status=$?
fi

# textlint uses 1 for lint findings. Other failures should not trap the agent in
# a retry loop, but surface the failure so the check is not silently skipped.
if [ "$lint_status" -ne 1 ]; then
  notify
  jq -n --arg message "AI 文体検査を実行できませんでした。textlint の終了コード: $lint_status" '{systemMessage: $message}'
  exit 0
fi

# A Stop hook continuation causes another Stop event. Permit at most one rewrite
# to avoid looping on a false positive or a finding that cannot be resolved.
if printf '%s' "$payload" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then
  notify
  message="AI 文体の指摘が書き直し後も残っています:
$lint_output"
  jq -n --arg message "$message" '{systemMessage: $message}'
  exit 0
fi

reason="最終回答に AI 文体のパターンが検出されました。指摘箇所だけを自然で簡潔な文章に修正し、修正を反映した最終回答の全文を再出力してください。修正部分だけを出力してはいけません。指摘箇所以外の内容、根拠、コマンド、ファイルパス、引用は変更しないでください。

$lint_output"
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
