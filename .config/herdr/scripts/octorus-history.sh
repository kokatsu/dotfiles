#!/bin/bash
# octorus rally履歴ブラウザ (herdr版)
# Alt-h でfzfを起動し、選択したファイルパスをClaude Code/Codexに送信する

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}
RALLY_DIR="$HOME/.cache/octorus/rally"

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

if [[ ! -d "$RALLY_DIR" ]]; then
  echo "No octorus rally data found"
  read -r
  exit 1
fi

# 現在のリポジトリに絞り込む (owner_repo プレフィックスでフィルタ)
# リポジトリ名にドットを含むケース (e.g. owner_repo.name) に対応
# origin がないリポジトリ (or リポジトリ外) では絞り込まない
repo_prefix=$(git remote get-url origin 2>/dev/null |
  sed -E 's/(\.git)?$//; s#.*[:/]([^/]+)/(.+)$#\1_\2#') || repo_prefix=""

files=$(fd -e json --type f --exclude session.json . "$RALLY_DIR" \
  --exec-batch ls -t)

if [[ -n "$repo_prefix" ]]; then
  files=$(echo "$files" | grep -F "/$repo_prefix") || files=""
fi

if [[ -z "$files" ]]; then
  echo "No rally data found for this repository"
  read -r
  exit 0
fi

# fzf のキャンセル (exit 130) を set -e で落とさず、空選択として扱う
selected=$(echo "$files" |
  fzf --preview 'bat --color=always --language=json {}' \
    --preview-window=right:60% \
    --delimiter '/' \
    --with-nth -3,-2,-1) || true

if [[ -n "$selected" ]]; then
  "$herdr_bin" pane send-text "$active_pane_id" "$selected"
fi
