#!/bin/bash
# 起動元ペインの Claude Code セッションの応答を fzf で選び、クリップボードへコピーする。
# /copy N は番号でしか過去の応答を選べないため、プレビューで中身を見ながら選ぶ。
# 一覧は新しい順で、assistant の text ブロック 1 つを 1 件とする

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

# agent_session は SessionStart フック (.config/herdr/hooks/report-agent-session.sh) が報告する
session_id=$("$herdr_bin" pane get "$active_pane_id" |
  jq -r 'select(.result.pane.agent == "claude") | .result.pane.agent_session.value // empty')
if [[ -z "$session_id" ]]; then
  notify "Claude Code のペインではありません"
  exit 0
fi

shopt -s nullglob
transcripts=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$session_id".jsonl)
if ((${#transcripts[@]} == 0)); then
  notify "セッションの会話ログが見つかりません" "$session_id"
  exit 0
fi

dir=$(mktemp -d -t copy-claude-response.XXXXXX)
trap 'rm -rf "$dir"' EXIT

n=0
while IFS= read -r -d '' text; do
  n=$((n + 1))
  printf '%s' "$text" >"$dir/$n.md"
done < <(jq -j 'select(.type == "assistant" and (.isSidechain | not) and (.isApiErrorMessage | not))
  | .message.content[]? | select(.type == "text")
  | .text | sub("\\A\\s+"; "") | sub("\\s+\\z"; "") | select(. != "") | . + "\u0000"' \
  "${transcripts[0]}")

if ((n == 0)); then
  notify "コピーできる応答がありません"
  exit 0
fi

# fzf のキャンセル (exit 130) を set -e で落とさず、空選択として扱う
chosen=$(for ((i = n; i >= 1; i--)); do
  printf '%s\t%s\n' "$i" "$(head -n 1 "$dir/$i.md")"
done |
  fzf --delimiter '\t' --with-nth 2 --no-sort \
    --preview "bat --color=always --style=plain --language=md $dir/{1}.md" \
    --preview-window=right:60%:wrap) || true

[[ -z "$chosen" ]] && exit 0
file="$dir/${chosen%%$'\t'*}.md"
copy_to_clipboard <"$file"
notify "Claude の応答をコピーしました"
