#!/bin/bash
# Herdr の agent list 順で、現在位置より後にある blocked エージェントへ移動する。
# 末尾まで見つからなければ先頭へ折り返す。

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

notify() {
  "$herdr_bin" notification show "$1" --sound none >/dev/null 2>&1 || true
}

if ! agents_json=$("$herdr_bin" agent list); then
  notify "エージェント一覧の取得に失敗しました"
  exit 1
fi

if ! agents=$(jq -ce '.result.agents | select(type == "array")' <<<"$agents_json"); then
  notify "エージェント一覧の解析に失敗しました"
  exit 1
fi

target_pane_id=$(
  jq -r --arg current "$active_pane_id" '
    . as $agents
    | ($agents | map(.pane_id) | index($current)) as $current_index
    | if $current_index == null then
        [$agents[] | select(.agent_status == "blocked") | .pane_id][0] // empty
      else
        [
          range(1; ($agents | length) + 1) as $offset
          | $agents[(($current_index + $offset) % ($agents | length))]
          | select(.agent_status == "blocked")
          | .pane_id
        ][0] // empty
      end
  ' <<<"$agents"
)

if [[ -z "$target_pane_id" ]]; then
  notify "blocked のエージェントはありません"
  exit 0
fi

if ! "$herdr_bin" agent focus "$target_pane_id"; then
  notify "blocked エージェントへの移動に失敗しました"
  exit 1
fi
