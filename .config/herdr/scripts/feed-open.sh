#!/bin/bash
# 未読フィードをブラウザで開く
# Alt-r で fzf を起動し、選択したフィードの URL をブラウザで開く
# データ生成 (feed-watch systemd timer) が WSL 限定のため実質 WSL 専用
#
# `[[ ... ]] && ... && exit 0` は && リストの非末尾コマンドの失敗として扱われる
# ため set -e では終了しない。fzf キャンセル時は pipefail で assignment が失敗
# して終了するが、直後の空チェックと結果は同じ

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# status-dir の失敗 (Windows 側ユーザーを解決できない) で set -e により
# 無言終了しないよう、空パスに倒して下の未検出メッセージへ流す
status_dir=$("$HOME/.local/bin/scripts/status-dir" feed-watch) || status_dir=""
STATUS_FILE="$status_dir/status.json"

[[ ! -f "$STATUS_FILE" ]] && echo "No feed-watch data found" && read -r && exit 0

# 未読のあるフィードを "url<TAB>表示ラベル" で列挙
entries=$(jq -r '.feeds | to_entries[]
  | select(.value.unread_count > 0 and .value.url != null)
  | [.value.url, .value.type // "rss", .key, (.value.unread_count | tostring)]
  | @tsv' "$STATUS_FILE")

[[ -z "$entries" ]] && echo "未読フィードはありません" && read -r && exit 0

selected=$(echo "$entries" |
  awk -F'\t' '{icon = ($2 == "github") ? "" : "󰑫"; printf "%s\t%s %s (%s)\n", $1, icon, $3, $4}' |
  sort -t$'\t' -k2 |
  fzf --delimiter '\t' --with-nth 2 |
  cut -f1)

[[ -z "$selected" ]] && exit 0

open_url "$selected"
