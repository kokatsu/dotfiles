#!/bin/bash
# Lazygit を一時ペインで開く (herdr版)
# prefix+l で起動 (alt+l は nvim mini.move と衝突するため prefix 側)

set -euo pipefail

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

exec lazygit
