#!/bin/bash
# close_pane (prefix+x) の置き換え。エージェントが idle (緑) 以外の
# working / blocked / done のときは即閉じせず、close-confirm プラグインの
# overlay 確認画面を開く (y の 1 キーで確定)。
# prefix+z (zoom) との押し間違いで稼働中エージェントを失う事故の防止。
#
# popup 型 custom command だと即閉じパスでも一瞬ポップアップが描画され、
# トースト (delivery=terminal) は気付きにくいため、shell 型 + 必要時のみ
# plugin pane open で確認 UI を出す構成にしている。
# placement は manifest 側の popup 指定に任せる (0.7.5 の CLI --placement は
# popup を受け付けないが、manifest とサーバー API は対応済み)。

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

pane_json=$("$herdr_bin" pane get "$active_pane_id")
status=$(jq -r '.result.pane.agent_status // "none"' <<<"$pane_json")

# エージェントなしの素のシェルは unknown を返す。UI では unknown は idle (緑)
# として描画されるため即閉じ側に含める
case "$status" in
none | idle | unknown)
  exec "$herdr_bin" pane close "$active_pane_id"
  ;;
esac

title=$(jq -r '.result.pane.terminal_title_stripped // ""' <<<"$pane_json")
exec "$herdr_bin" plugin pane open \
  --plugin kokatsu.close-confirm --entrypoint confirm \
  --focus \
  --env TARGET_PANE_ID="$active_pane_id" \
  --env TARGET_STATUS="$status" \
  --env TARGET_TITLE="$title"
