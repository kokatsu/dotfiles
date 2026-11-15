#!/bin/bash
# 起動元ペインのエージェントに、会話のリセット (new) または終了 (quit) の
# スラッシュコマンドを送る。名前がエージェントごとに違うため送信時に振り分ける。
#
# Usage: send-agent-command.sh <new|quit>

set -euo pipefail

active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}
# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"

agent=$("$herdr_bin" pane get "$active_pane_id" | jq -r '.result.pane.agent // ""') || agent=""
case "$agent:${1:?usage: send-agent-command.sh <new|quit>}" in
pi:new) command=/new ;;
pi:quit) command=/quit ;;
*:new) command=/clear ;;
*:quit) command=/exit ;;
*)
  notify "未知の操作です: $1"
  exit 1
  ;;
esac

exec "$herdr_bin" agent prompt "$active_pane_id" "$command"
