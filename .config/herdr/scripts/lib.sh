#!/bin/bash
# 各 herdr スクリプトから source して使う (単体で実行しない)

herdr_bin=${HERDR_BIN_PATH:-herdr}

notify() {
  "$herdr_bin" notification show "$1" ${2:+--body "$2"} --sound none >/dev/null 2>&1 || true
}

# bin/wsl-open は PowerShell の Constrained Language Mode を避けるため wslview を
# 置き換えたもの。PATH 経由で見つからない場合は配置先の絶対パスへ倒す。
# macOS を先に分けるのは、bin/ が macOS でも PATH に入るため wsl-open が必ず
# 見つかってしまい、中の cmd.exe 実行で落ちて後段まで来ないから
open_url() {
  if [[ $(uname -s) == Darwin ]]; then
    /usr/bin/open "$1"
  elif command -v wsl-open >/dev/null 2>&1; then
    wsl-open "$1"
  elif [[ -x "$HOME/.local/bin/scripts/wsl-open" ]]; then
    "$HOME/.local/bin/scripts/wsl-open" "$1"
  else
    xdg-open "$1" >/dev/null 2>&1 || open "$1" >/dev/null 2>&1
  fi
}

copy_to_clipboard() {
  if [[ $(uname -s) == Darwin ]]; then
    pbcopy
  else
    xsel -ib
  fi
}

# 新しいペインの ID を出力する。ratio の既定は 0.5
split_pane() {
  local response
  response=$(
    "$herdr_bin" pane split "$1" \
      --direction "$2" \
      --ratio "${3:-0.5}" \
      --no-focus \
      ${HERDR_ACTIVE_PANE_CWD:+--cwd "$HERDR_ACTIVE_PANE_CWD"}
  )
  jq -er '.result.pane.pane_id' <<<"$response"
}

# 標準入力の改行区切りのパスを、起動元ペインのエージェントに合わせた形で送る。
# herdr は 1 キー = 1 コマンド固定で bind 時点の振り分けができないため、
# 送信時に herdr pane get の .result.pane.agent (なしは null) で判定する。
# Codex CLI は入力欄で "@" を打つと内蔵 fuzzy picker が開くため "@" を付けない。
# $PWD 配下のパスは $PWD からの相対パスにする
send_paths() {
  local pane_id=$1 agent p payload=""
  # 取得に失敗しても中断せず、シェル向けの形式にフォールバックする
  agent=$("$herdr_bin" pane get "$pane_id" |
    jq -r '.result.pane.agent // ""') || agent=""
  # 最終行が改行で終わらない場合にも読み取れるよう `|| [[ -n "$p" ]]` を付ける
  while IFS= read -r p || [[ -n "$p" ]]; do
    [[ -z "$p" ]] && continue
    [[ $p == / ]] || p=${p%/}
    case "$p" in
    "$PWD") p=. ;;
    "$PWD"/*) p=${p#"$PWD"/} ;;
    esac
    case "$agent" in
    claude) payload+="@${p} " ;;
    codex) payload+="${p} " ;;
    # シェルなど: コマンド引数としてそのまま使えるようクォートする
    *) payload+="$(printf '%q' "$p") " ;;
    esac
  done
  [[ -n "$payload" ]] || return 0
  "$herdr_bin" pane send-text "$pane_id" "$payload"
}
