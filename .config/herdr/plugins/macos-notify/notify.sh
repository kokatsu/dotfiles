#!/usr/bin/env bash
set -euo pipefail

event=${HERDR_PLUGIN_EVENT_JSON:?}
status=$(jq -r '.data.agent_status // empty' <<<"$event")
case "$status" in
blocked | done) ;;
*) exit 0 ;;
esac
pane_id=$(jq -er '.data.pane_id | select(type == "string" and length > 0)' <<<"$event")
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Herdr は子プロセスの stdout/stderr が閉じるまで実行枠を保持する。
# クリック待ちは別プロセスにし、パイプも継承させない。
nohup bash "$plugin_dir/show.sh" "$pane_id" "$status" \
  </dev/null >/dev/null 2>>"${HERDR_PLUGIN_STATE_DIR:?}/notifications.log" &
