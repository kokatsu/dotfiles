#!/bin/bash
# パス選択スクリプト (fzf版, herdr版)
# Alt-c で fzf を起動し、選択したパスを Claude Code / Codex CLI に送信する
# 複数選択 (Tab) 対応、bat プレビュー付き
#
# herdr は 1 キー = 1 コマンド固定で bind 時点の振り分けができないため、
# 起動元ペインのエージェントを herdr pane get で調べて実行時に判定する。
# foreground process 名の手動マッチではなく herdr 自身の検出結果
# (.result.pane.agent) を使う。エージェントなしのペインは null
#
# Codex CLI は入力欄で "@" を打つと内蔵fuzzy pickerが開く仕様のため、
# "@" prefixを付けずに相対パス文字列だけを送る。

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

# fzf のキャンセル (exit 130) を set -e で落とさず、空選択として扱う
selected=$(fd --type f --hidden --no-ignore --exclude .git --exclude node_modules . |
  fzf --multi \
    --preview 'bat --color=always --style=numbers {} 2>/dev/null || cat {}' \
    --preview-window=right:60%) || true

[[ -z "$selected" ]] && exit 0

# 取得に失敗しても中断せず、Claude 形式にフォールバックする
agent=$("$herdr_bin" pane get "$active_pane_id" |
  jq -r '.result.pane.agent // ""') || agent=""

if [[ "$agent" == codex ]]; then
  # Codex: "@" を付けずスペース区切り
  payload=$(printf '%s\n' "$selected" | tr '\n' ' ')
else
  # Claude: "@path1 @path2 " 形式
  payload=$(printf '%s\n' "$selected" | sed 's|^|@|' | tr '\n' ' ')
fi

"$herdr_bin" pane send-text "$active_pane_id" "$payload"
