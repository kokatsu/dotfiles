#!/bin/bash
# 未読フィードをブラウザで開く (herdr版)
# Alt-r で fzf を起動し、選択したフィードの URL をブラウザで開く
# WezTerm 版 Alt+r (keybinds.lua、コメントアウト済み) の herdr 移植。
# データ生成 (feed-watch systemd timer) が WSL 限定のため実質 WSL 専用

# feed-watch (bin/scripts/feed-watch) と同じ Windows 側出力先の解決
get_status_dir() {
  local winuser
  winuser=$(/mnt/c/Windows/System32/cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r') || true
  if [[ -n "$winuser" && -d "/mnt/c/Users/$winuser" ]]; then
    echo "/mnt/c/Users/$winuser/.cache/feed-watch"
    return
  fi

  # Fallback: /mnt/c/Users からシステム以外のディレクトリを探す
  local d base
  for d in /mnt/c/Users/*/; do
    base=$(basename "$d")
    case "$base" in
    Public | Default | "Default User" | "All Users") continue ;;
    esac
    echo "${d}.cache/feed-watch"
    return
  done

  return 1
}

STATUS_FILE="$(get_status_dir)/status.json"

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

if command -v wslview >/dev/null 2>&1; then
  wslview "$selected"
else
  open "$selected" 2>/dev/null || xdg-open "$selected"
fi
