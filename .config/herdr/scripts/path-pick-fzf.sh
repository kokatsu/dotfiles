#!/bin/bash
# パス選択スクリプト (fzf版, herdr版)
# Alt-c で fzf を起動し、選択したパスを Claude Code / Codex CLI に送信する
# 複数選択 (Tab) 対応、bat プレビュー付き
# tmux版: .config/tmux/scripts/claude-path-pick-fzf.sh, codex-path-pick-fzf.sh
#
# tmux版はbind時点でpane_current_commandからagentを判定して別スクリプトに
# 振り分けていたが、herdrは1キー=1コマンド固定で振り分けができないため、
# 起動元ペインのforeground processをherdr pane process-infoで調べて
# このスクリプト内で実行時に判定する。
#
# Codex CLI は入力欄で "@" を打つと内蔵fuzzy pickerが開く仕様のため、
# "@" prefixを付けずに相対パス文字列だけを送る。

set -euo pipefail

cd "$HERDR_ACTIVE_PANE_CWD"

selected=$(fd --type f --hidden --no-ignore --exclude .git --exclude node_modules . |
  fzf --multi \
    --preview 'bat --color=always --style=numbers {} 2>/dev/null || cat {}' \
    --preview-window=right:60%)

[[ -z "$selected" ]] && exit 0

if herdr pane process-info --pane "$HERDR_ACTIVE_PANE_ID" |
  jq -e 'any(.result.process_info.foreground_processes[]?; .name == "codex")' >/dev/null 2>&1; then
  # Codex: "@" を付けずスペース区切り
  payload=$(printf '%s\n' "$selected" | tr '\n' ' ')
else
  # Claude: "@path1 @path2 " 形式
  payload=$(printf '%s\n' "$selected" | sed 's|^|@|' | tr '\n' ' ')
fi

herdr pane send-text "$HERDR_ACTIVE_PANE_ID" "$payload"
