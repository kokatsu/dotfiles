#!/bin/bash
# WezTerm の open-uri (ファイルパスのクリック) から呼ばれ、herdr の新規タブの nvim で開く
# 使い方: open-in-nvim.sh <path> [line]
# WezTerm からはフォーカス中の herdr ペインの cwd が見えないため、相対パスはここで解決する

set -euo pipefail

file=$1
line=${2:-}

focused=$(herdr pane list | jq -c '.result.panes[] | select(.focused)')
cwd=$(jq -r '.foreground_cwd // .cwd' <<<"$focused")
workspace=$(jq -r '.workspace_id' <<<"$focused")

[[ $file == /* ]] || file="$cwd/$file"

pane=$(herdr tab create --workspace "$workspace" --cwd "$cwd" --focus | jq -r '.result.root_pane.pane_id')
# 先頭の空白で履歴に残さず (hist_ignore_space)、exec で nvim 終了時にタブごと閉じる
herdr pane run "$pane" " exec nvim ${line:++$line }$(printf '%q' "$file")"
