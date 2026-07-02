#!/bin/bash
# octorus rally履歴ブラウザ (herdr版)
# Alt-h でfzfを起動し、選択したファイルパスをClaude Code/Codexに送信する
# tmux版: .config/tmux/scripts/octorus-history.sh

RALLY_DIR="$HOME/.cache/octorus/rally"

cd "$HERDR_ACTIVE_PANE_CWD" 2>/dev/null || true

[[ ! -d "$RALLY_DIR" ]] && echo "No octorus rally data found" && read -r && exit 1

# 現在のリポジトリに絞り込む (owner_repo プレフィックスでフィルタ)
# リポジトリ名にドットを含むケース (e.g. owner_repo.name) に対応
repo_prefix=$(git remote get-url origin 2>/dev/null |
  sed -E 's/(\.git)?$//; s#.*[:/]([^/]+)/(.+)$#\1_\2#')

files=$(fd -e json --type f --exclude session.json . "$RALLY_DIR" \
  --exec-batch ls -t)

if [[ -n "$repo_prefix" ]]; then
  files=$(echo "$files" | grep -F "/$repo_prefix")
fi

[[ -z "$files" ]] && echo "No rally data found for this repository" && read -r && exit 0

selected=$(echo "$files" |
  fzf --preview 'bat --color=always --language=json {}' \
    --preview-window=right:60% \
    --delimiter '/' \
    --with-nth -3,-2,-1)

[[ -n "$selected" ]] && herdr pane send-text "$HERDR_ACTIVE_PANE_ID" "$selected"
