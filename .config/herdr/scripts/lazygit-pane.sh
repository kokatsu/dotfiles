#!/bin/bash
# Lazygit を一時ペインで開く (herdr版)
# prefix+l で起動 (alt+l は nvim mini.move と衝突するため prefix 側)

cd "$HERDR_ACTIVE_PANE_CWD" 2>/dev/null || true

exec lazygit
