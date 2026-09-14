#!/usr/bin/env bash
# 異常のあるサービスの Statuspage をブラウザで開く
#
# status-watch が書くキャッシュを読み、正常でないサービスだけを開く。ステータス
# バーのアイコンが色付いたときに「何が起きているか」を確認する動線なので、fzf で
# 選ばせず該当するものを直接開く。すべて正常なら通知だけ出して何も開かない。

set -euo pipefail

# format.lua と同じ TTL。これを超えたデータは監視が止まっているとみなす
TTL=900

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
status_dir=${STATUS_WATCH_STATUS_DIR:-$("$HOME/.local/bin/scripts/status-dir" status-watch)} || {
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
