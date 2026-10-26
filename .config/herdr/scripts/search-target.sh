#!/bin/bash

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if [[ ${1:-} == --preview ]]; then
  details=$(jq -ce --arg kind "$3" --arg id "$4" '
    .result.snapshot as $s
    | (if $kind == "tab" then $id else
        [$s.panes[] | select(.pane_id == $id) | .tab_id][0] end) as $tab_id
    | $s.tabs[] | select(.tab_id == $tab_id) | . as $tab
    | [$s.panes[] | select(.tab_id == $tab_id)
        | . as $p | . + ([$s.agents[] | select(.pane_id == $p.pane_id)][0] // {})] as $panes
    | ([$s.layouts[]? | select(.tab_id == $tab_id) | .focused_pane_id][0]) as $focused
    | (if $kind == "agent" then $id else $focused end) as $pane_id
    | ($panes | map(select(.pane_id == $pane_id))[0] // .[0]) as $pane
    | {tab: $tab.label,
        workspace: ([$s.workspaces[] | select(.workspace_id == $tab.workspace_id) | .label][0]),
        pane: $pane, panes: $panes}
  ' "$2") || exit 0

  jq -r '
    def clean: (. // "") | gsub("[\u0000-\u001f\u007f]"; " ");
    "ワークスペース: \(.workspace | clean)",
    "タブ: \(.tab | clean)",
    "作業名: \(.pane.terminal_title_stripped // .pane.name | clean)",
    "状態: \(.pane.agent // "shell") / \(.pane.agent_status // "unknown")",
    "ディレクトリ: \(.pane.foreground_cwd // .pane.cwd | clean)"
  ' <<<"$details"
  if [[ $3 == tab ]]; then
    printf '\nペイン一覧\n'
    jq -r '.pane.pane_id as $current | .panes[]
      | [(if .pane_id == $current then ">" else " " end),
          (.agent // "shell"), (.agent_status // "unknown"),
          (.terminal_title_stripped // .name // .foreground_cwd // .cwd // "")]
      | map(gsub("[\u0000-\u001f\u007f]"; " ")) | join(" ")' <<<"$details"
  fi
  pane_id=$(jq -r '.pane.pane_id // empty' <<<"$details")
  [[ -n "$pane_id" ]] || exit 0
  printf '\n── 端末の直近出力 ──\n'
  if ! "$herdr_bin" pane read "$pane_id" --source recent --lines 50 --format text --raw 2>/dev/null; then
    printf '端末出力を取得できませんでした（ペインが閉じられた可能性があります）\n'
  fi
  exit 0
fi

if ! snapshot=$("$herdr_bin" api snapshot); then
  notify "タブ・エージェント一覧の取得に失敗しました"
  exit 1
fi

if ! targets=$(jq -er --slurpfile colors "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/search-colors.json" '
  def color($name):
    "\u001b[38;2;" + ($colors[0][$name] | map(tostring) | join(";")) + "m" + . + "\u001b[39m";
  def decorate:
    ({claude: "peach", codex: "blue", "タブ": "mauve"}[.[2]] // "subtext0") as $kind_color
    | ({working: ["◐", "yellow"], blocked: ["!", "red"], done: ["✓", "green"],
        idle: ["○", "overlay1"], unknown: ["?", "overlay1"]}[.[3]] // ["?", "overlay1"]) as $state
    | .[2] |= color($kind_color)
    | .[3] = ($state[0] + " " + .[3] | color($state[1]))
    | .[4] |= color("subtext0")
    | .[5] |= color("subtext0");
  .result.snapshot
  | select((.workspaces | type) == "array" and (.tabs | type) == "array" and (.agents | type) == "array" and (.panes | type) == "array")
  | . as $s
  | [
      .workspaces[] as $ws
      | $s.tabs[] | select(.workspace_id == $ws.workspace_id) | . as $tab
      | ([$s.layouts[]? | select(.tab_id == $tab.tab_id) | .focused_pane_id][0]) as $focused
      | ([$s.panes[] | select(.tab_id == $tab.tab_id)] | map(select(.pane_id == $focused))[0] // .[0]) as $pane
      | ["tab", .tab_id, "タブ", (.agent_status // "unknown"), $ws.label, .label,
          "", ($pane.foreground_cwd // $pane.cwd // "")],
        ($s.agents[] | select(.tab_id == $tab.tab_id)
          | ["agent", .pane_id, .agent, (.agent_status // "unknown"), $ws.label, $tab.label,
              (.terminal_title_stripped // .name // ""), (.foreground_cwd // .cwd // "")])
    ]
  | map(map(. // "" | gsub("[\u0000-\u001f\u007f]"; " ")) | decorate | join("\t")) | join("\n")
' <<<"$snapshot"); then
  notify "タブ・エージェント一覧を作成できませんでした"
  exit 1
fi

if [[ -z "$targets" ]]; then
  notify "検索できるタブ・エージェントがありません"
  exit 0
fi

snapshot_file=$(mktemp -t herdr-search.XXXXXX)
trap 'rm -f "$snapshot_file"' EXIT
printf '%s\n' "$snapshot" >"$snapshot_file"
self=$(printf '%q' "$0")
preview_snapshot=$(printf '%q' "$snapshot_file")

if chosen=$(fzf --ansi --delimiter '\t' --with-nth 3..8 --no-sort --height=100% \
  --preview "bash $self --preview $preview_snapshot {1} {2}" --preview-window=right:60%:wrap \
  --prompt '作業を検索> ' --header 'Enter: 移動 / Esc: キャンセル' <<<"$targets"); then
  [[ -n "$chosen" ]] || exit 0
else
  status=$?
  case "$status" in
  1 | 130) exit 0 ;;
  esac
  notify "作業検索に失敗しました"
  exit "$status"
fi

IFS=$'\t' read -r kind target _ <<<"$chosen"
case "$kind" in
tab | agent)
  if ! "$herdr_bin" "$kind" focus "$target" >/dev/null; then
    notify "選択した作業へ移動できませんでした" "タブやエージェントが閉じられた可能性があります"
    exit 1
  fi
  ;;
esac
