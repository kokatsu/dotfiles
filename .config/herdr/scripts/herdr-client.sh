#!/bin/bash
# herdr クライアントを起動し、実行中だけ WezTerm の user var HERDR_CLIENT を立てる
# Windows の WezTerm からは WSL 内のプロセス名が見えないため、wezterm.lua はこれで herdr を見分ける
# OSC 1337 の組み立ては .config/zsh/functions.zsh の _wezterm_set_user_var と同じ

printf '\033]1337;SetUserVar=HERDR_CLIENT=%s\007' "$(printf 1 | base64)"
rc=0
herdr || rc=$?
printf '\033]1337;SetUserVar=HERDR_CLIENT=\007'
exit "$rc"
