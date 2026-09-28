#!/bin/bash
# WezTerm の open-uri (ファイルパスのクリック) から呼ばれ、同じタブの nvim が 1 つならそこで、それ以外は herdr の新規タブの nvim で開く
# 使い方: open-in-nvim.sh <path> [line]
# WezTerm からはフォーカス中の herdr ペインの cwd が見えないため、相対パスはここで解決する

set -euo pipefail

file=$1
line=${2:-}

focused=$(herdr pane list | jq -c '.result.panes[] | select(.focused)')
cwd=$(jq -r '.foreground_cwd // .cwd' <<<"$focused")
workspace=$(jq -r '.workspace_id' <<<"$focused")

[[ $file == /* ]] || file="$cwd/$file"

tab=$(jq -r '.tab_id' <<<"$focused")
nvim_pids=$(
  herdr pane list | jq -r --arg tab "$tab" '.result.panes[] | select(.tab_id == $tab) | .pane_id' |
    while read -r p; do
      herdr pane process-info --pane "$p" |
        jq -r '.result.process_info.foreground_processes[] | select(.name == "nvim") | .pid'
    done
)

# 同じタブの nvim がちょうど 1 つなら (pid が 1 行だけ) そこで開く。接続できなければ新規タブへ
# Neovim 0.12 の RPC サーバーは TUI ではなく子の --embed プロセスの pid でソケットを作る
if [[ $nvim_pids =~ ^[0-9]+$ ]] && embed=$(pgrep -P "$nvim_pids" -f 'nvim --embed'); then
  quote="''"
  # ソケットの場所は :h serverstart() の規則に従う (macOS には XDG_RUNTIME_DIR がない)
  for server in ${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp/}nvim.$USER/*}/nvim."$embed".0; do
    nvim --server "$server" --remote-expr \
      "execute('edit ${line:++$line }' .. fnameescape('${file//\'/$quote}'))" >/dev/null && exit
  done
fi

pane=$(herdr tab create --workspace "$workspace" --cwd "$cwd" --focus | jq -r '.result.root_pane.pane_id')
# 先頭の空白で履歴に残さず (hist_ignore_space)、exec で nvim 終了時にタブごと閉じる
herdr pane run "$pane" " exec nvim ${line:++$line }$(printf '%q' "$file")"
