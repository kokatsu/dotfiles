#!/bin/bash
# 1 ペインなら、現在のペインを全幅の上段とする 3 ペインの作業レイアウトを作成する。
# すでにこの形の 3 ペインなら、上段で Claude Code、右下で Codex が起動していなければ起動する。
#
# ┌───────────────────┐
# │      claude       │
# │                   │
# ├─────────┬─────────┤
# │  shell  │  codex  │
# └─────────┴─────────┘

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

# 上段が 1 枚で、残り 2 枚が同じ高さに並ぶときだけ「上段 右下」の ID を出す
find_layout_panes() {
  jq -er '
    .result.layout.panes as $panes
    | ($panes | map(.rect.y) | min) as $top_y
    | [$panes[] | select(.rect.y == $top_y)] as $top
    | [$panes[] | select(.rect.y != $top_y)] as $bottom
    | select(($top | length) == 1 and ($bottom | length) == 2)
    | select($bottom[0].rect.y == $bottom[1].rect.y)
    | [$top[0].pane_id, ($bottom | max_by(.rect.x) | .pane_id)]
    | @tsv
  '
}

notify_unsupported_layout() {
  notify "上段全幅レイアウトを適用できません" \
    "1ペイン、または上段全幅の3ペインで実行してください (現在: $1)"
}

layout=$("$herdr_bin" pane layout --pane "$active_pane_id")
pane_count=$(jq -er '.result.layout.panes | length' <<<"$layout")

if ((pane_count == 3)); then
  pane_ids=$(find_layout_panes <<<"$layout") || {
    notify_unsupported_layout "3ペイン"
    exit 0
  }
  IFS=$'\t' read -r top_pane_id bottom_right_pane_id <<<"$pane_ids"

  start_agent_if_needed "$top_pane_id" claude
  start_agent_if_needed "$bottom_right_pane_id" codex
  exit 0
fi

if ((pane_count != 1)); then
  notify_unsupported_layout "${pane_count}ペイン"
  exit 0
fi

bottom_pane_id=$(split_pane "$active_pane_id" down 0.65)
split_pane "$bottom_pane_id" right 0.5 >/dev/null
