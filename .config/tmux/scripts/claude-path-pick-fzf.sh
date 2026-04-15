#!/bin/bash
# Claude Code用パス選択スクリプト (fzf版)
# Alt-c で fzf を起動し、選択したパスを @path 形式で Claude Code に送信する
# 複数選択 (Tab) 対応、bat プレビュー付き

set -euo pipefail

# display-popup -d で起動元ペインの CWD が pwd になっている
selected=$(fd --type f --hidden --no-ignore --exclude .git --exclude node_modules . |
  fzf --multi \
    --preview 'bat --color=always --style=numbers {} 2>/dev/null || cat {}' \
    --preview-window=right:60%)

[[ -z "$selected" ]] && exit 0

# 複数行を "@path1 @path2 " に変換
payload=$(printf '%s\n' "$selected" | sed 's|^|@|' | tr '\n' ' ')

tmux send-keys -l "$payload"
