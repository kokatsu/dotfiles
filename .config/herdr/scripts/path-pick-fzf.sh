#!/bin/bash
# パス選択スクリプト (fzf版, herdr版)
# Alt-c で fzf を起動し、選択したパスを起動元ペイン (Claude Code / Codex CLI / シェル) に送信する
# ファイルとディレクトリを fuzzy に絞り込めるほか、Ctrl-l で選択中のディレクトリへ潜り、
# Ctrl-h で親へ上がれる。複数選択 (Tab) 対応、プレビュー付き

set -euo pipefail

# bash 5 は置換文字列の ~ を $HOME に展開し直すため、変数経由で渡す
tilde='~'

# fzf の reload / preview / transform から自身を呼ぶ。fzf の action は状態を持てないため、
# 現在の起点ディレクトリは状態ファイルに置く。各行は "起点<TAB>起点からの相対パス" で、
# 起点を行に持たせることで、別のディレクトリで選んだパスも復元できる。
# fzf は reload で選択を解除するので、移動前の選択は "$state.picked" に退避しておく
case "${1:-}" in
--list)
  root=$(<"$2")
  # git リポジトリの外 (ホーム等) を再帰列挙すると百万件を超えて fzf が詰まり、
  # 後続の reload が画面に反映されなくなる。外では 1 階層だけ出して辿る用途に絞る
  depth=1
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && depth=
  fd --type f --type d --hidden --no-ignore --exclude .git --exclude node_modules \
    ${depth:+--max-depth="$depth"} --base-directory "$root" . |
    R=$root awk '{ print ENVIRON["R"] "\t" $0 }'
  exit 0
  ;;
--preview)
  p=${2%/}/$3
  if [[ -d "$p" ]]; then
    eza --tree --level=2 --color=always "$p"
  else
    bat --color=always --style=numbers "$p" 2>/dev/null || cat "$p"
  fi
  exit 0
  ;;
--chdir)
  state=$2
  if [[ "$4" == .. ]]; then
    new=$(dirname "$(<"$state")")
  else
    new=${4%/}/${5%/}
    [[ -n "${5:-}" && -d "$new" ]] || exit 0
  fi
  # 未選択でも {+f} はカーソル行を含むため、選択数で判定する
  if ((${FZF_SELECT_COUNT:-0} > 0)); then
    cat "$3" >>"$state.picked"
  fi
  printf '%s\n' "$new" >"$state"
  prompt=${new/#"$HOME"/$tilde}
  printf 'reload(%q --list %q)+clear-query+first+change-prompt:%s/ > ' \
    "$0" "$state" "${prompt%/}"
  exit 0
  ;;
esac

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

state=$(mktemp -t path-pick-fzf.XXXXXX)
trap 'rm -f "$state" "$state.picked"' EXIT
printf '%s\n' "$PWD" >"$state"
self=$(printf '%q' "$0")
state_q=$(printf '%q' "$state")

# fzf のキャンセル (exit 130) を set -e で落とさず、空選択として扱う
chosen=$("$0" --list "$state" |
  fzf --multi \
    --delimiter '\t' --with-nth 2 \
    --prompt "${PWD/#"$HOME"/$tilde}/ > " \
    --header 'Ctrl-l: ディレクトリへ潜る / Ctrl-h: 親へ上がる' \
    --bind "ctrl-l:transform:$self --chdir $state_q {+f} {1} {2}" \
    --bind "ctrl-h:transform:$self --chdir $state_q {+f} .." \
    --preview "$self --preview {1} {2}" \
    --preview-window=right:60%) || true

[[ -z "$chosen" ]] && exit 0
selected=$({
  [[ -f "$state.picked" ]] && cat "$state.picked"
  printf '%s\n' "$chosen"
} | awk '!seen[$0]++')

while IFS=$'\t' read -r root rel; do
  printf '%s\n' "${root%/}/${rel%/}"
done <<<"$selected" | send_paths "$active_pane_id"
