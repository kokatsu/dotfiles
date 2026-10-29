#!/bin/bash
# クリップボードの画像を起動元ペインのリポジトリに保存し、そのパスをペインへ送る。
# devcontainer の Claude Code はホストのクリップボードを読めないため、画像をパスで渡す

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

if ! image=$(save-clipboard-image 2>/dev/null); then
  notify "画像を保存できませんでした" "クリップボードに画像が無いか、ペインの cwd が git リポジトリの外です"
  exit 1
fi

printf '%s\n' "$image" | send_paths "$active_pane_id"
