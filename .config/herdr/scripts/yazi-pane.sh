#!/bin/bash
# Yazi を一時ペインで開く (herdr版)
# Alt-y で起動。アクティブペインの cwd から開き、ファイルは opener 設定
# (nvim, block) でそのまま編集できる

cd "$HERDR_ACTIVE_PANE_CWD" 2>/dev/null || true

exec yazi
