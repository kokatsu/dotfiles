#!/usr/bin/env bash
set -euo pipefail

# Herdr サーバーはログインシェルの Homebrew PATH を引き継がない場合がある。
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

pane_id=${1:?}
status=${2:?}
herdr_bin=${HERDR_BIN_PATH:?}
socket=${HERDR_SOCKET_PATH:?}

case "$status" in
blocked) message='入力・承認が必要です' ;;
done) message='作業が完了しました' ;;
*) exit 0 ;;
esac

# 組み込み通知と同じく、一時的な状態変化と表示中のタブは通知しない。
sleep 1
panes=$("$herdr_bin" pane list)
pane=$(jq -c --arg id "$pane_id" --arg status "$status" '
  .result.panes as $panes
  | ($panes | map(select(.focused) | .tab_id)) as $active_tabs
  | $panes[]
  | select(.pane_id == $id and .agent_status == $status)
  | select(.tab_id as $tab | $active_tabs | index($tab) | not)
' <<<"$panes")
[[ -n "$pane" ]] || exit 0

agent=$(jq -r '.agent // "agent"' <<<"$pane")
title=$(jq -r '[.terminal_title_stripped, .label, .cwd, .pane_id] | map(select(type == "string" and length > 0)) | first' <<<"$pane")
result=$(alerter \
  --title "Herdr · $agent" \
  --subtitle "$title" \
  --message "$message" \
  --group "herdr:$socket:$pane_id" \
  --json)

case "$(jq -r '.activationType' <<<"$result")" in
contentsClicked | actionClicked)
  "$herdr_bin" agent focus "$pane_id" >/dev/null
  open -b com.github.wez.wezterm
  ;;
esac
