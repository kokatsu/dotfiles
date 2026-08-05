#!/bin/bash
# 選択中のペインを指定方向の隣接ペインと入れ替える。

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}
direction=${1:?direction is required}

case "$direction" in
left | right | up | down) ;;
*)
  printf 'unknown direction: %s\n' "$direction" >&2
  exit 2
  ;;
esac

exec "$herdr_bin" pane swap --pane "$active_pane_id" --direction "$direction"
