#!/bin/bash
# Yazi (yazi-pane.sh) のキーから呼び、引数のパスを起動元ペインへ送信する。
# Yazi の shell は Yazi 側の cwd で動くため、起動元ペインの cwd へ戻ってから
# 相対パスを作る

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

printf '%s\n' "$@" | send_paths "$active_pane_id"
