#!/bin/bash
# 現在のペインを左上として、4 ペインの作業レイアウトを作成する。
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
cwd_args=()

if [[ -n "${HERDR_ACTIVE_PANE_CWD:-}" ]]; then
  cwd_args=(--cwd "$HERDR_ACTIVE_PANE_CWD")
fi

# 既に分割されているタブでは、既存レイアウトをさらに細分化しない。
layout=$("$herdr_bin" pane layout --pane "$active_pane_id")
pane_count=$(jq -er '.result.layout.panes | length' <<<"$layout")

if ((pane_count != 1)); then
  "$herdr_bin" notification show \
    "4ペインレイアウトを適用できません" \
    --body "現在のタブは既に ${pane_count} ペインに分割されています" \
    --sound none >/dev/null
  exit 0
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

# 左右を 1:1 に分割し、作成された右ペインの ID を保持する。
right_pane_id=$(split_pane "$active_pane_id" right 0.5)

# 元の左ペインは上 3:下 1、右ペインは上 1:下 1 に分割する。
split_pane "$active_pane_id" down 0.75 >/dev/null
split_pane "$right_pane_id" down 0.5 >/dev/null
