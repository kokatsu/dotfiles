#!/bin/bash
# Claude Code用プロンプト編集スクリプト (herdr版)
# Alt-v でNeovimを起動し、編集後に内容をClaude Codeに送信する
# tmux版: .config/tmux/scripts/claude-prompt-edit.sh
# https://zenn.dev/shisashi/articles/0ba22e272d6f2f

set -euo pipefail

# .claude 拡張子で専用設定を適用しつつ、mktemp -d で衝突・漏洩を回避
TMPDIR_PROMPT=$(mktemp -d -t claude-prompt.XXXXXX)
TMPFILE="$TMPDIR_PROMPT/prompt.claude"
trap 'rm -rf "$TMPDIR_PROMPT"' EXIT

# Neovimでインサートモードで開始
nvim -c "startinsert" "$TMPFILE"

# 内容が存在する場合のみ送信
if [[ -s "$TMPFILE" ]]; then
  CONTENT=$(cat "$TMPFILE")

  # herdrのペインが閉じた後、起動元ペインに内容を送信
  herdr pane send-text "$HERDR_ACTIVE_PANE_ID" "$CONTENT"
fi
