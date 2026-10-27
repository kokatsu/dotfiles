#!/bin/bash

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"

default_prompt='作業を検索> '
priority_prompt='作業を検索 [要対応優先]> '

list_targets() {
  jq -er --arg order "$2" --slurpfile colors "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/search-colors.json" '
  def color($name):
    "\u001b[38;2;" + ($colors[0][$name] | map(tostring) | join(";")) + "m" + . + "\u001b[39m";
  def decorate:
    ({claude: "peach", codex: "blue"}[.[1]] // "subtext0") as $kind_color
    | ({working: ["◐", "yellow"], blocked: ["!", "red"], done: ["✓", "green"],
        idle: ["○", "overlay1"], unknown: ["?", "overlay1"]}[.[2]] // ["?", "overlay1"]) as $state
    | .[1] |= color($kind_color)
    | if .[2] == "" then . else .[2] = ($state[0] + " " + .[2] | color($state[1])) end
    | .[3] |= color("subtext0")
    | .[4] |= color("subtext0");
  .result.snapshot
  | select((.workspaces | type) == "array" and (.tabs | type) == "array" and (.panes | type) == "array")
  | . as $s
  | [
      .workspaces[] as $ws
      | $s.tabs[] | select(.workspace_id == $ws.workspace_id) | . as $tab
      | $s.panes[] | select(.tab_id == $tab.tab_id)
      | [.pane_id, (.agent // "shell"), (if .agent then .agent_status // "unknown" else "" end),
          $ws.label, $tab.label, (.terminal_title_stripped // .name // ""), (.foreground_cwd // .cwd // "")]
    ]
  | if $order == "priority" then sort_by({blocked: 0, done: 1}[.[2]] // 2) else . end
  | map(map(. // "" | gsub("[\u0000-\u001f\u007f]"; " ")) | decorate | join("\t")) | join("\n")
' "$1"
}

if [[ ${1:-} == --list ]]; then
  list_targets "$2" "$3"
  exit
fi

if [[ ${1:-} == --toggle ]]; then
  if [[ ${FZF_PROMPT:-} == "$priority_prompt" ]]; then
    order=default prompt=$default_prompt
  else
    order=priority prompt=$priority_prompt
  fi
  printf 'change-prompt(%s)+reload(bash %q --list %q %s)\n' "$prompt" "$0" "$2" "$order"
  exit
fi

if [[ ${1:-} == --preview ]]; then
  details=$(jq -r --arg id "$3" '
    def clean: (. // "") | gsub("[\u0000-\u001f\u007f]"; " ");
    .result.snapshot as $s
    | $s.panes[] | select(.pane_id == $id) | . as $p
    | "ワークスペース: \([$s.workspaces[] | select(.workspace_id == $p.workspace_id) | .label][0] | clean)",
      "タブ: \([$s.tabs[] | select(.tab_id == $p.tab_id) | .label][0] | clean)",
      "作業名: \($p.terminal_title_stripped // $p.name | clean)",
      "状態: \(if $p.agent then "\($p.agent) / \($p.agent_status // "unknown")" else "shell" end)",
      "ディレクトリ: \($p.foreground_cwd // $p.cwd | clean)"
  ' "$2") || exit 0
  [[ -n "$details" ]] || exit 0
  printf '%s\n\n── 端末の直近出力 ──\n' "$details"
  if ! "$herdr_bin" pane read "$3" --source recent --lines 50 --format text --raw 2>/dev/null; then
    printf '端末出力を取得できませんでした（ペインが閉じられた可能性があります）\n'
  fi
  exit 0
fi

if ! snapshot=$("$herdr_bin" api snapshot); then
  notify "ペイン一覧の取得に失敗しました"
  exit 1
fi

snapshot_file=$(mktemp -t herdr-search.XXXXXX)
trap 'rm -f "$snapshot_file"' EXIT
printf '%s\n' "$snapshot" >"$snapshot_file"

if ! targets=$(list_targets "$snapshot_file" default); then
  notify "ペイン一覧を作成できませんでした"
  exit 1
fi

if [[ -z "$targets" ]]; then
  notify "検索できるペインがありません"
  exit 0
fi

self=$(printf '%q' "$0")
preview_snapshot=$(printf '%q' "$snapshot_file")

if chosen=$(fzf --ansi --delimiter '\t' --with-nth 2..7 --no-sort --height=100% \
  --preview "bash $self --preview $preview_snapshot {1}" --preview-window=right:60%:wrap \
  --bind "ctrl-s:transform:bash $self --toggle $preview_snapshot" \
  --prompt "$default_prompt" --header 'Enter: 移動 / Ctrl-S: 並び順を切替 / Esc: キャンセル' <<<"$targets"); then
  [[ -n "$chosen" ]] || exit 0
else
  status=$?
  case "$status" in
  1 | 130) exit 0 ;;
  esac
  notify "作業検索に失敗しました"
  exit "$status"
fi

IFS=$'\t' read -r pane_id _ <<<"$chosen"
# herdr CLI の pane focus は隣接ペインへの移動しかないため、ソケット API で ID を指定する
if ! jq -cn --arg pane "$pane_id" '{id: "search-target", method: "pane.focus", params: {pane_id: $pane}}' |
  socat - "UNIX-CONNECT:${HERDR_SOCKET_PATH:?}" | jq -e '.result' >/dev/null; then
  notify "選択したペインへ移動できませんでした" "ペインが閉じられた可能性があります"
  exit 1
fi
