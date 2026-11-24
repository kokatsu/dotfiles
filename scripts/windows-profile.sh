# shellcheck shell=bash

# 引数の cmd.exe から Windows の %USERPROFILE% を取得する。取得できなければ何も出力しない
read_userprofile() {
  local vars profile
  # echo %USERPROFILE% だと、値に含まれる & を cmd.exe がコマンドの区切りとして解釈する
  vars=$("$1" /C "set USERPROFILE" 2>/dev/null | tr -d '\r') || vars=""
  # set は USERPROFILE で始まる変数をすべて出力する
  profile=${vars:+$'\n'$vars}
  profile=${profile#*$'\n'USERPROFILE=}
  printf '%s' "${profile%%$'\n'*}"
}
