#!/bin/bash
# 各 herdr スクリプトから source して使う (単体で実行しない)

herdr_bin=${HERDR_BIN_PATH:-herdr}

notify() {
  "$herdr_bin" notification show "$1" --sound none >/dev/null 2>&1 || true
}

# bin/wsl-open は PowerShell の Constrained Language Mode を避けるため wslview を
# 置き換えたもの。PATH 経由で見つからない場合は配置先の絶対パスへ倒す。
# macOS を先に分けるのは、bin/ が macOS でも PATH に入るため wsl-open が必ず
# 見つかってしまい、中の cmd.exe 実行で落ちて後段まで来ないから
open_url() {
  if [[ $(uname -s) == Darwin ]]; then
    /usr/bin/open "$1"
  elif command -v wsl-open >/dev/null 2>&1; then
    wsl-open "$1"
  elif [[ -x "$HOME/.local/bin/scripts/wsl-open" ]]; then
    "$HOME/.local/bin/scripts/wsl-open" "$1"
  else
    xdg-open "$1" >/dev/null 2>&1 || open "$1" >/dev/null 2>&1
  fi
}
