#!/bin/bash
# WezTerm の open-uri (ファイルパスのクリック) から呼ばれ、herdr の同じタブの nvim か新規タブの nvim で開く
# 使い方:
#   open-in-nvim.sh --existing-only <path> [line]
#     同じタブの nvim がちょうど 1 つならそこで開いて exit 0。それ以外は exit 1 し、stdout の
#     1 行目に <絶対パス>\t<cwd>\t<workspace>、2 行目以降に nvim が複数あるときの候補 <ソケット>\t<ラベル> を出す
#   open-in-nvim.sh --new-tab --cwd <cwd> --workspace <workspace> <絶対パス> [line]
#   open-in-nvim.sh --server <ソケット> --cwd <cwd> --workspace <workspace> <絶対パス> [line]
#     指定の nvim で開き、開けなければ新規タブで開く
# WezTerm からはフォーカス中の herdr ペインの cwd が見えないため、相対パスは --existing-only で解決する

set -euo pipefail

mode='' server='' cwd='' workspace=''
while [[ ${1:-} == --* ]]; do
  case $1 in
  --existing-only | --new-tab)
    mode=${1#--}
    shift
    ;;
  --server)
    mode=server server=$2
    shift 2
    ;;
  --cwd)
    cwd=$2
    shift 2
    ;;
  --workspace)
    workspace=$2
    shift 2
    ;;
  *)
    echo "open-in-nvim: unknown option: $1" >&2
    exit 2
    ;;
  esac
done
file=$1
line=${2:-}

# 失敗時に E492 などを出しても exit 0 になるため、stdout が ok かで判定する
open_in() {
  local quote="''"
  [[ $(nvim --server "$1" --remote-expr \
    "[execute('edit ${line:++$line }' .. fnameescape('${file//\'/$quote}')), 'ok'][1]" 2>/dev/null) == ok ]]
}

new_tab() {
  local pane
  pane=$(herdr tab create --workspace "$workspace" --cwd "$cwd" --focus | jq -r '.result.root_pane.pane_id')
  # 先頭の空白で履歴に残さず (hist_ignore_space)、exec で nvim 終了時にタブごと閉じる
  herdr pane run "$pane" " exec nvim ${line:++$line }$(printf '%q' "$file")"
}

case $mode in
new-tab)
  new_tab
  exit
  ;;
server)
  open_in "$server" || new_tab
  exit
  ;;
esac

panes=$(herdr pane list)
focused=$(jq -c '.result.panes[] | select(.focused)' <<<"$panes")
cwd=$(jq -r '.foreground_cwd // .cwd' <<<"$focused")
workspace=$(jq -r '.workspace_id' <<<"$focused")
tab=$(jq -r '.tab_id' <<<"$focused")

[[ $file == /* ]] || file="$cwd/$file"

# 同じタブの nvim ごとに RPC ソケットを 1 行ずつ集める
# Neovim 0.12 の RPC サーバーは TUI ではなく子の --embed プロセスの pid でソケットを作る
sockets=()
while read -r p; do
  pids=$(herdr pane process-info --pane "$p" |
    jq -r '.result.process_info.foreground_processes[] | select(.name == "nvim") | .pid')
  for pid in $pids; do
    embed=$(pgrep -P "$pid" -f 'nvim --embed') || continue
    # ソケットの場所は :h serverstart() の規則に従う (macOS には XDG_RUNTIME_DIR がない)
    for s in ${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp/}nvim.$USER/*}/nvim."$embed".0; do
      [[ -S $s ]] && sockets+=("$s")
    done
  done
done < <(jq -r --arg tab "$tab" '.result.panes[] | select(.tab_id == $tab) | .pane_id' <<<"$panes")

if ((${#sockets[@]} == 1)) && open_in "${sockets[0]}"; then
  exit
fi

printf '%s\t%s\t%s\n' "$file" "$cwd" "$workspace"
if ((${#sockets[@]} > 1)); then
  for s in "${sockets[@]}"; do
    label=$(nvim --server "$s" --remote-expr \
      "(empty(bufname()) ? '[No Name]' : expand('%:~:.')) .. '  ' .. fnamemodify(getcwd(), ':~')" 2>/dev/null) || continue
    printf '%s\t%s\n' "$s" "$label"
  done
fi
exit 1
