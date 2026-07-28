#!/bin/bash
# close-confirm プラグインの確認画面本体。close-pane-confirm.sh が
# --env で渡す対象ペイン情報を表示し、y の 1 キーで閉じる。

set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
target=${TARGET_PANE_ID:?TARGET_PANE_ID is not set}
status=${TARGET_STATUS:-unknown}
title=${TARGET_TITLE:-}

printf '\n  対象: %s (%s)\n  エージェントが %s 状態です。閉じますか? [y/N] ' \
  "${title:-名称なし}" "$target" "$status"
IFS= read -r -n 1 ans || ans=""
echo

case "$ans" in
y | Y)
  # pane close の JSON レスポンスが popup に一瞬表示されるのを抑止
  exec "$herdr_bin" pane close "$target" >/dev/null 2>&1
  ;;
esac
