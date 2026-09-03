#!/usr/bin/env bash
# 異常のあるサービスの Statuspage をブラウザで開く
#
# status-watch が書くキャッシュを読み、正常でないサービスだけを開く。ステータス
# バーのアイコンが色付いたときに「何が起きているか」を確認する動線なので、fzf で
# 選ばせず該当するものを直接開く。すべて正常なら通知だけ出して何も開かない。

set -euo pipefail

# format.lua と同じ TTL。これを超えたデータは監視が止まっているとみなす
TTL=900

herdr_bin=${HERDR_BIN_PATH:-herdr}

notify() {
  "$herdr_bin" notification show "$1" --sound none >/dev/null 2>&1 || true
}

# status-watch の get_status_dir と同じ解決
get_status_dir() {
  if [[ -n "${STATUS_WATCH_STATUS_DIR:-}" ]]; then
    echo "$STATUS_WATCH_STATUS_DIR"
    return
  fi

  if [[ $(uname -s) == Darwin ]]; then
    echo "$HOME/.cache/status-watch"
    return
  fi

  local winuser
  winuser=$(/mnt/c/Windows/System32/cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r') || true
  if [[ -n "$winuser" && -d "/mnt/c/Users/$winuser" ]]; then
    echo "/mnt/c/Users/$winuser/.cache/status-watch"
    return
  fi

  return 1
}

# bin/wsl-open は PowerShell の Constrained Language Mode を避けるため wslview を
# 置き換えたもの。PATH 経由で見つからない場合は配置先の絶対パスへ倒す。
# macOS を先に分けるのは、bin/ が macOS でも PATH に入るため wsl-open が必ず
# 見つかってしまい、中の cmd.exe 実行で落ちて後段まで来ないから
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

status_dir=$(get_status_dir) || {
  notify "キャッシュディレクトリを解決できませんでした"
  exit 1
}

# キャッシュのファイル名|表示名|Statuspage の URL
services=(
  "status.json|Claude|https://status.claude.com/"
  "openai.json|OpenAI|https://status.openai.com/"
  "github.json|GitHub|https://www.githubstatus.com/"
)

now=$(date +%s)
opened=()
stale=()

for entry in "${services[@]}"; do
  IFS='|' read -r file label url <<<"$entry"
  path="$status_dir/$file"

  if [[ ! -f "$path" ]]; then
    stale+=("$label")
    continue
  fi

  if ! IFS=$'\t' read -r indicator generated components incidents < <(
    jq -r '[.indicator // "unknown", .last_updated // 0, (.components | length), (.incidents | length)] | @tsv' "$path" 2>/dev/null
  ); then
    stale+=("$label")
    continue
  fi

  if ((now - generated > TTL)); then
    stale+=("$label")
    continue
  fi

  # format.lua と同じ判定。indicator が none でも component 異常や未解決の
  # incident があれば異常として扱う
  if [[ $indicator != none ]] || ((components > 0)) || ((incidents > 0)); then
    open_url "$url"
    opened+=("$label")
  fi
done

if ((${#opened[@]} > 0)); then
  notify "Statuspage を開きました: ${opened[*]}"
elif ((${#stale[@]} > 0)); then
  notify "異常はありません (監視停止: ${stale[*]})"
else
  notify "3 サービスすべて正常です"
fi
