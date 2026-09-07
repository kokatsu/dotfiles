#!/bin/bash
# 未読フィードをブラウザで開く
# Alt-r で fzf を起動し、選択したフィードの URL をブラウザで開く
# データ生成 (feed-watch systemd timer) が WSL 限定のため実質 WSL 専用
#
# `[[ ... ]] && ... && exit 0` は && リストの非末尾コマンドの失敗として扱われる
# ため set -e では終了しない。fzf キャンセル時は pipefail で assignment が失敗
# して終了するが、直後の空チェックと結果は同じ

set -euo pipefail

# feed-watch (bin/feed-watch) と同じ Windows 側出力先の解決
get_status_dir() {
  local winuser
  winuser=$(/mnt/c/Windows/System32/cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r') || true
  if [[ -n "$winuser" && -d "/mnt/c/Users/$winuser" ]]; then
    echo "/mnt/c/Users/$winuser/.cache/feed-watch"
    return
  fi

  # cmd.exe が使えないときは WSL ユーザー名と同名のプロファイルだけを候補にする
  # (feed-watch と同じ規則。/mnt/c/Users/* の先頭を拾う推測はしない)
  if [[ -d "/mnt/c/Users/$USER" ]]; then
    echo "/mnt/c/Users/$USER/.cache/feed-watch"
    return
  fi

  return 1
}

# bin/wsl-open は PowerShell の Constrained Language Mode を避けるため wslview を
# 置き換えたもの (status-open.sh と同じ解決順)。
open_url() {
  if [[ $(uname -s) == Darwin ]]; then
    /usr/bin/open "$1"
  elif command -v wsl-open >/dev/null 2>&1; then
    wsl-open "$1"
  elif [[ -x "$HOME/.local/bin/scripts/wsl-open" ]]; then
    "$HOME/.local/bin/scripts/wsl-open" "$1"
  else
    xdg-open "$1" >/dev/null 2>&1 || open "$1" >/dev/null 2>&1
  fi
}

# get_status_dir の失敗 (Windows 側ユーザーを解決できない) で set -e により
# 無言終了しないよう、空パスに倒して下の未検出メッセージへ流す
status_dir=$(get_status_dir) || status_dir=""
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
