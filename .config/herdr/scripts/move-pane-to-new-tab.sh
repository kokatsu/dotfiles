#!/bin/bash
# 現在のペインを元のプロセスを維持したまま新しいタブへ移動する。

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

exec "$herdr_bin" pane move "$active_pane_id" --new-tab --focus
