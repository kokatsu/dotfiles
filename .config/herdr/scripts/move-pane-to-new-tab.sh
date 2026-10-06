#!/bin/bash
# 現在のペインを元のプロセスを維持したまま新しいタブへ移動する。

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

exec "$herdr_bin" pane move "$active_pane_id" --new-tab --focus
