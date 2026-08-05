#!/bin/bash
# 1 ペイン、または上下 2 分割のタブを、片側が全高でもう片側が
# 上下 1:1 の 3 ペインにする。既存ペインのプロセスは維持する。

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}
full_height_side=${1:?full-height side is required}
cwd_args=()

case "$full_height_side" in
full-left | full-right) ;;
*)
  printf 'unknown full-height side: %s\n' "$full_height_side" >&2
  exit 2
  ;;
esac

if [[ -n "${HERDR_ACTIVE_PANE_CWD:-}" ]]; then
  cwd_args=(--cwd "$HERDR_ACTIVE_PANE_CWD")
fi

split_pane() {
  local target_pane_id=$1
  local direction=$2
  local response

  response=$(
    "$herdr_bin" pane split "$target_pane_id" \
      --direction "$direction" \
      --ratio 0.5 \
      --no-focus \
      "${cwd_args[@]}"
  )

  jq -er '.result.pane.pane_id' <<<"$response"
}

move_pane() {
  local pane_id=$1
  local target_pane_id=$2
  local direction=$3
  local destination_tab_id=$4
  local focus_arg=--no-focus
  local response

  if [[ "$pane_id" == "$active_pane_id" ]]; then
    focus_arg=--focus
  fi

  response=$(
    "$herdr_bin" pane move "$pane_id" \
      --tab "$destination_tab_id" \
      --target-pane "$target_pane_id" \
      --split "$direction" \
      --ratio 0.5 \
      "$focus_arg"
  )

  jq -er '
    select(.result.move_result.changed == true)
    | .result.move_result.pane.pane_id
  ' <<<"$response"
}

notify_unsupported_layout() {
  local current=$1

  "$herdr_bin" notification show \
    "3ペインレイアウトを適用できません" \
    --body "1ペイン、または上下2分割のタブで実行してください (現在: ${current})" \
    --sound none >/dev/null
}

# shellcheck disable=SC2329  # EXIT trap から間接的に呼び出す。
notify_restore_failure() {
  "$herdr_bin" notification show \
    "ペインを元のタブへ戻せませんでした" \
    --body "一時タブに残ったペインを手動で戻してください" \
    --sound none >/dev/null
}

layout=$("$herdr_bin" pane layout --pane "$active_pane_id")
pane_count=$(jq -er '.result.layout.panes | length' <<<"$layout")
original_tab_id=$(jq -er '.result.layout.tab_id' <<<"$layout")

# zoom 中のタブでは pane move が changed:false / zoomed_tab を exit 0 で返し、
# optional な created_tab が null になるため、ここで弾く。
if [[ $(jq -er '.result.layout.zoomed' <<<"$layout") == true ]]; then
  notify_unsupported_layout "ズーム中"
  exit 0
fi

if ((pane_count == 1)); then
  right_pane_id=$(split_pane "$active_pane_id" right)

  if [[ "$full_height_side" == "full-left" ]]; then
    # 同一タブ内の pane move は変更なしになるため、元ペインを一時タブへ
    # 退避してから、新しいペインの右へ戻す。
    move_response=$("$herdr_bin" pane move "$active_pane_id" --new-tab --no-focus)
    active_pane_id=$(jq -er '
      select(.result.move_result.changed == true)
      | .result.move_result.pane.pane_id
    ' <<<"$move_response")

    active_is_temporary=true
    # shellcheck disable=SC2329  # EXIT trap から間接的に呼び出す。
    restore_active_on_exit() {
      if [[ "$active_is_temporary" == true ]]; then
        set +e
        "$herdr_bin" pane move "$active_pane_id" \
          --tab "$original_tab_id" \
          --target-pane "$right_pane_id" \
          --split right \
          --ratio 0.5 \
          --focus >/dev/null 2>&1
      fi
    }
    trap restore_active_on_exit EXIT

    active_pane_id=$(move_pane "$active_pane_id" "$right_pane_id" right "$original_tab_id")
    active_is_temporary=false
    trap - EXIT
    split_pane "$active_pane_id" down >/dev/null
  else
    # 元のペインを左上として左下を追加し、新しい右ペインを全高にする。
    split_pane "$active_pane_id" down >/dev/null
  fi
  exit 0
fi

is_vertical_pair=$(
  jq -r '
    .result.layout as $layout
    | ($layout.panes | length == 2)
      and ($layout.splits | length == 1)
      and ($layout.splits[0].direction == "down")
  ' <<<"$layout"
)

if [[ "$is_vertical_pair" != "true" ]]; then
  # ペイン数だけでは 2 ペインが拒否される理由が伝わらないため、分割方向を出す。
  notify_unsupported_layout "$(
    jq -er '
      .result.layout as $layout
      | ($layout.panes | length) as $count
      | if $count == 2
          and ($layout.splits | length) == 1
          and $layout.splits[0].direction == "right"
        then "左右2分割"
        else "\($count)ペイン"
        end
    ' <<<"$layout"
  )"
  exit 0
fi

pane_ids=$(jq -er '.result.layout.panes | sort_by(.rect.y) | map(.pane_id) | @tsv' <<<"$layout")
IFS=$'\t' read -r top_pane_id bottom_pane_id <<<"$pane_ids"

# 下ペインを一時タブへ退避すると、元タブの分割ルートが上ペインへ畳まれる。
bottom_was_active=false
if [[ "$bottom_pane_id" == "$active_pane_id" ]]; then
  bottom_was_active=true
fi

move_response=$("$herdr_bin" pane move "$bottom_pane_id" --new-tab --no-focus)
bottom_pane_id=$(jq -er '
  select(.result.move_result.changed == true)
  | .result.move_result.pane.pane_id
' <<<"$move_response")
temporary_tab_id=$(jq -er '.result.move_result.created_tab.tab_id' <<<"$move_response")
if [[ "$bottom_was_active" == true ]]; then
  active_pane_id=$bottom_pane_id
fi

# 以降で失敗しても、退避した既存ペインを可能な限り元タブへ戻す。
bottom_is_temporary=true
top_is_temporary=false
right_pane_id=
# shellcheck disable=SC2329  # EXIT trap から間接的に呼び出す。
restore_bottom_on_exit() {
  if [[ "$bottom_is_temporary" != true ]]; then
    return
  fi

  set +e
  local restore_target=$top_pane_id
  local degraded=false
  local move_response restored top_tab_id bottom_tab_id

  if [[ "$top_is_temporary" == true ]]; then
    move_response=$(
      "$herdr_bin" pane move "$top_pane_id" \
        --tab "$original_tab_id" \
        --target-pane "$right_pane_id" \
        --split right \
        --ratio 0.5 \
        --no-focus 2>/dev/null
    )
    # 元タブへ移動できたときだけ、返却された ID を下ペインの復元先にする。
    restored=$(jq -r --arg tab "$original_tab_id" '
      select(.result.move_result.changed == true)
      | select(.result.move_result.target_layout.tab_id == $tab)
      | .result.move_result.pane.pane_id // empty
    ' <<<"$move_response")

    if [[ -n "$restored" ]]; then
      top_pane_id=$restored
      restore_target=$top_pane_id
    else
      # 応答を取得できなくても移動自体は適用されうるので、所属タブを見て判断する。
      top_tab_id=$(
        "$herdr_bin" pane layout --pane "$top_pane_id" 2>/dev/null |
          jq -r '.result.layout.tab_id // empty'
      )
      if [[ "$top_tab_id" != "$original_tab_id" ]]; then
        # 上ペインは一時タブに残っている。元タブに残る右ペインへ下ペインを戻す。
        restore_target=$right_pane_id
        degraded=true
      fi
    fi
  fi

  if [[ -z "$restore_target" ]]; then
    notify_restore_failure
    return
  fi

  # 下ペインも移動拒否は changed:false / exit 0 で返るため、終了コードだけでは判断しない。
  move_response=$(
    "$herdr_bin" pane move "$bottom_pane_id" \
      --tab "$original_tab_id" \
      --target-pane "$restore_target" \
      --split down \
      --ratio 0.5 \
      --no-focus 2>/dev/null
  )
  restored=$(jq -r --arg tab "$original_tab_id" '
    select(.result.move_result.changed == true)
    | select(.result.move_result.target_layout.tab_id == $tab)
    | .result.move_result.pane.pane_id // empty
  ' <<<"$move_response")

  if [[ -z "$restored" ]]; then
    # 応答を取得できなくても移動自体は適用されうるので、所属タブを見て判断する。
    bottom_tab_id=$(
      "$herdr_bin" pane layout --pane "$bottom_pane_id" 2>/dev/null |
        jq -r '.result.layout.tab_id // empty'
    )
    if [[ "$bottom_tab_id" != "$original_tab_id" ]]; then
      degraded=true
    fi
  fi

  if [[ "$degraded" == true ]]; then
    notify_restore_failure
  fi
}
trap restore_bottom_on_exit EXIT

right_pane_id=$(split_pane "$top_pane_id" right)

if [[ "$full_height_side" == "full-left" ]]; then
  # 上ペインも一時タブへ移すと、新しいペインだけが元タブのルートに残る。
  # そこへ上・下ペインを順に戻して右列を復元する。
  top_was_active=false
  if [[ "$top_pane_id" == "$active_pane_id" ]]; then
    top_was_active=true
  fi

  top_pane_id=$(move_pane "$top_pane_id" "$bottom_pane_id" right "$temporary_tab_id")
  top_is_temporary=true
  if [[ "$top_was_active" == true ]]; then
    active_pane_id=$top_pane_id
  fi

  top_pane_id=$(move_pane "$top_pane_id" "$right_pane_id" right "$original_tab_id")
  top_is_temporary=false
  if [[ "$top_was_active" == true ]]; then
    active_pane_id=$top_pane_id
  fi
fi

# 右を全高にする場合は既存の上下ペインを左列でそのまま復元する。
bottom_pane_id=$(move_pane "$bottom_pane_id" "$top_pane_id" down "$original_tab_id")
bottom_is_temporary=false
trap - EXIT
