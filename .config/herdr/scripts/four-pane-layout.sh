#!/bin/bash
# 現在のペインを左上として、4 ペインの作業レイアウトを作成する。
# 右上で Claude Code、右下で Codex が起動していなければ起動する。
#
# ┌─────────┬─────────┐
# │         │         │
# │   3     │    1    │
# │         ├─────────┤
# ├─────────┤    1    │
# │   1     │         │
# └─────────┴─────────┘

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}
shell_name=${SHELL##*/}
cwd_args=()

if [[ -n "${HERDR_ACTIVE_PANE_CWD:-}" ]]; then
  cwd_args=(--cwd "$HERDR_ACTIVE_PANE_CWD")
fi

split_pane() {
  local target_pane_id=$1
  local direction=$2
  local ratio=$3
  local response

  response=$(
    "$herdr_bin" pane split "$target_pane_id" \
      --direction "$direction" \
      --ratio "$ratio" \
      --no-focus \
      "${cwd_args[@]}"
  )

  jq -er '.result.pane.pane_id' <<<"$response"
}

start_agent_if_needed() {
  local pane_id=$1
  local agent=$2
  local pane_state
  local process_info

  process_info=$("$herdr_bin" pane process-info --pane "$pane_id")
  pane_state=$(
    jq -er --arg agent "$agent" --arg shell "$shell_name" '
      .result.process_info.foreground_processes as $processes
      | select($processes | type == "array")
      | if any($processes[]?; .name == $agent) then
          "running"
        elif ($processes | length) > 0
          and all($processes[]; .name == $shell)
        then
          "shell"
        else
          "busy"
        end
    ' <<<"$process_info"
  )

  if [[ "$pane_state" == shell ]]; then
    "$herdr_bin" pane run "$pane_id" "$agent" >/dev/null
  fi
}

find_right_panes() {
  jq -er '
    .result.layout.panes as $panes
    | ($panes | map(.rect.x) | max) as $right_x
    | [$panes[] | select(.rect.x == $right_x) | { pane_id, rect }] as $right
    | select($right | length == 2)
    | select($right[0].rect.width == $right[1].rect.width)
    | ($right | sort_by(.rect.y) | map(.pane_id) | @tsv)
  '
}

notify_unsupported_layout() {
  local current=$1

  "$herdr_bin" notification show \
    "4ペインレイアウトを適用できません" \
    --body "1ペイン、または右列が上下分割された4ペインで実行してください (現在: ${current})" \
    --sound none >/dev/null
}

layout=$("$herdr_bin" pane layout --pane "$active_pane_id")
pane_count=$(jq -er '.result.layout.panes | length' <<<"$layout")

if ((pane_count == 4)); then
  right_pane_ids=$(find_right_panes <<<"$layout") || {
    notify_unsupported_layout "4ペイン"
    exit 0
  }
  IFS=$'\t' read -r right_top_pane_id right_bottom_pane_id <<<"$right_pane_ids"

  start_agent_if_needed "$right_top_pane_id" claude
  start_agent_if_needed "$right_bottom_pane_id" codex
  exit 0
fi

if ((pane_count != 1)); then
  notify_unsupported_layout "${pane_count}ペイン"
  exit 0
fi

# 左右を 1:1 に分割し、作成された右ペインの ID を保持する。
right_pane_id=$(split_pane "$active_pane_id" right 0.5)

# 元の左ペインは上 3:下 1、右ペインは上 1:下 1 に分割する。
split_pane "$active_pane_id" down 0.75 >/dev/null
right_bottom_pane_id=$(split_pane "$right_pane_id" down 0.5)

"$herdr_bin" pane run "$right_pane_id" claude >/dev/null
"$herdr_bin" pane run "$right_bottom_pane_id" codex >/dev/null
