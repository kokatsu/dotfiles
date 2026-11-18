#!/bin/bash
# リポジトリの .kokatsu/prompts/*.md から定型プロンプトを fzf で選び、起動元ペインの
# エージェントへ送信する。1 ファイル 1 プロンプトで、ファイル名が一覧の表示名になる。
# .kokatsu はグローバル gitignore (nix/home/programs/git.nix) に入っている

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

# エージェント以外のペインで選ばせてから拒否しないよう、一覧を出す前に判定する
if ! agent=$("$herdr_bin" pane get "$active_pane_id" | jq -r '.result.pane.agent // ""'); then
  notify "ペイン情報を取得できません"
  exit 1
fi
if [[ -z "$agent" ]]; then
  notify "エージェントのペインではありません"
  exit 0
fi

if ! root=$(git -C "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}" \
  rev-parse --show-toplevel 2>/dev/null); then
  notify "Git リポジトリの外です"
  exit 0
fi
dir=$root/.kokatsu/prompts

shopt -s nullglob
files=("$dir"/*.md)
if ((${#files[@]} == 0)); then
  # macOS の /bin/bash 3.2 は置換文字列の \~ をそのまま残し、bash 5.2 以降は素の ~ を
  # $HOME に展開し直すため、変数経由で渡す
  tilde='~'
  notify "プロンプトがありません" "${dir/#"$HOME"/$tilde}/*.md"
  exit 0
fi

# fzf のキャンセル (exit 130) を set -e で落とさず、空選択として扱う
chosen=$(for f in "${files[@]}"; do
  f=${f##*/}
  printf '%s\n' "${f%.md}"
done |
  fzf --preview "bat --color=always --style=plain --language=md $(printf '%q' "$dir")/{}.md" \
    --preview-window=right:60%:wrap) || true

[[ -z "$chosen" ]] && exit 0
text=$(<"$dir/$chosen.md")
if [[ -z "$text" ]]; then
  notify "プロンプトが空です" "$chosen"
  exit 0
fi
if ! error=$("$herdr_bin" agent prompt "$active_pane_id" "$text" 2>&1 >/dev/null); then
  message=$(jq -r '.error.message // empty' <<<"$error" 2>/dev/null) || message=""
  notify "プロンプトを送信できませんでした" "${message:-$error}"
  exit 1
fi
