#!/usr/bin/env bash
# Desktop notification dispatch hook for Claude Code, shared by the Stop
# hook (turn end) and the Notification hook (permission prompt). $1 selects
# the event:
#   stop (default) — toast body is the last assistant message read from the
#     transcript, emitted 2.5s after the turn ends so the transcript has
#     flushed and Claude Code's end-of-turn TUI redraw has settled.
#   permission     — toast body is a fixed string, emitted 0.5s after the
#     permission prompt appears (no transcript read, smaller redraw).
#
# WSL branch resolves the Claude Code main process pts and writes a
# tmux-DCS-wrapped OSC 1337 SetUserVar=CLAUDE_LAST_MSG to it. WezTerm's
# user-var-changed handler in .config/wezterm/format.lua shows the toast.
# The OSC 1337 + tmux DCS construction mirrors _wezterm_set_user_var in
# .config/zsh/functions.zsh — kept in sync by hand since that helper is a
# zsh function unreachable from this sh subprocess.
#
# The pts write is deferred: the hook has no controlling terminal and its
# $PPID is an intermediate shell whose fd/1 is a pipe (not re-openable).
# terminalSequence JSON is not used: claude only wraps it in tmux DCS
# passthrough when its internal wR1() returns "tmux", which depends on the
# daemon/attacher caps and is unreliable here.

set -euo pipefail

event=${1:-stop}
payload=$(cat || true)

if [ -n "${CMUX_SURFACE_ID:-}" ]; then
  case "$event" in
  permission) printf '%s' "$payload" | cmux claude-hook notification 2>/dev/null || true ;;
  *) printf '%s' "$payload" | cmux claude-hook stop 2>/dev/null || true ;;
  esac
  exit 0
fi

if [ "$(uname)" = "Darwin" ]; then
  case "$event" in
  permission) alerter --title 'Claude Code' --message '権限の承認が必要です' --sound Glass >/dev/null 2>&1 || true ;;
  *) alerter --title 'Claude Code' --message 'タスクが完了しました' --sound Glass --timeout 10 >/dev/null 2>&1 || true ;;
  esac
  exit 0
fi

if ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  exit 0
fi

# 祖先をたどって Claude Code 本体を見つけ、その pts デバイスを得る。
# Stop hook の $PPID は中間 shell でその fd/1 は pipe（再オープン不可）。
claude_tty=''
pid=$PPID
for _ in 1 2 3 4 5 6 7 8; do
  case "$pid" in '' | 0 | 1) break ;; esac
  { read -r comm <"/proc/$pid/comm"; } 2>/dev/null || break
  if [ "$comm" = claude ]; then
    claude_tty=$(readlink "/proc/$pid/fd/1" 2>/dev/null || true)
    break
  fi
  # /proc/$pid/stat = "pid (comm) state ppid ..."; ppid は "(comm) " の後の 2 番目
  { read -r statline <"/proc/$pid/stat"; } 2>/dev/null || break
  statline=${statline##*") "}
  statline=${statline#* }
  pid=${statline%% *}
done

case "$claude_tty" in
/dev/pts/*) ;;
*) exit 0 ;;
esac
[ -w "$claude_tty" ] || exit 0

# permission は固定文言・即時寄り、stop は transcript 由来・再描画待ち。
# transcript の jq 抽出は stop かつ pts 確定後にのみ走らせ、同期パスの fork を省く。
case "$event" in
permission)
  delay=0.5
  fixed_msg='権限の承認が必要です'
  transcript=''
  ;;
*)
  delay=2.5
  fixed_msg=''
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  ;;
esac

# 遅延ジョブ: setsid で hook のプロセスグループから切り離し hook 本体は即 return。
# fixed_msg が空なら transcript の末尾から最後の assistant text を読む。
# shellcheck disable=SC2016
setsid sh -c '
  sleep "$4"
  tty=$1
  transcript=$2
  msg=$3
  if [ -z "$msg" ]; then
    msg="タスクが完了しました"
    if [ -n "$transcript" ]; then
      last=$(tail -n 50 "$transcript" 2>/dev/null | tac \
        | jq -r "select(.type==\"assistant\") | .message.content[]? | select(.type==\"text\") | .text" 2>/dev/null \
        | head -n 1)
      [ -n "$last" ] && msg=$last
    fi
  fi
  # head -c はバイト単位で切るため、日本語等のマルチバイト文字が途中で
  # 千切れて不正な UTF-8 になりうる。iconv -c で末尾の不完全シーケンスを落とす。
  msg=$(printf "%s" "$msg" | tr -d "[:cntrl:]" | head -c 200 | iconv -f UTF-8 -t UTF-8 -c)
  b64=$(printf "%s" "$msg" | base64 | tr -d "\n")
  printf "\033Ptmux;\033\033]1337;SetUserVar=CLAUDE_LAST_MSG=%s\007\033\\\\" "$b64" >"$tty" 2>/dev/null
' _ "$claude_tty" "$transcript" "$fixed_msg" "$delay" </dev/null >/dev/null 2>&1 &
