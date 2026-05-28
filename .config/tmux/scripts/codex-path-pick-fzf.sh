#!/bin/bash
# Codex CLI用パス選択スクリプト (fzf版)
# Alt-c で fzf を起動し、選択したパスをスペース区切りで Codex CLI に送信する
# 複数選択 (Tab) 対応、bat プレビュー付き
#
# claude-path-pick-fzf.sh との違い:
#   Codex CLI は入力欄で "@" を打つと内蔵 fuzzy picker が開く仕様のため、
#   "@" prefix を付けずに相対パス文字列だけを送る。Codex エージェントは
#   パスらしき token を認識して自律的に Read する。

set -euo pipefail

# display-popup -d で起動元ペインの CWD が pwd になっている
selected=$(fd --type f --hidden --no-ignore --exclude .git --exclude node_modules . |
  fzf --multi \
    --preview 'bat --color=always --style=numbers {} 2>/dev/null || cat {}' \
    --preview-window=right:60%)

[[ -z "$selected" ]] && exit 0

# 複数行を "path1 path2 " に変換 (claude 版と違い "@" は付けない)
payload=$(printf '%s\n' "$selected" | tr '\n' ' ')

tmux send-keys -l "$payload"
