#!/bin/bash
# Yazi を一時ペインで開く (herdr版)
# Alt-y で起動。アクティブペインの cwd から開き、ファイルは opener 設定
# (nvim, block) でそのまま編集できる

set -euo pipefail

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

exec yazi
