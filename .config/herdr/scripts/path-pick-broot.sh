#!/bin/bash
# パス選択スクリプト (broot版, herdr版)
# Alt-g で broot を起動。選択方法:
#   - ファイル上で Enter: 単一ファイル選択
#   - Ctrl+p: カレント選択 (ファイル/ディレクトリ両対応) を単一で確定
#   - Space: staging 切替 (複数選択)
#   - Ctrl+a: staged をまとめて確定
# 選択したパス (単一/複数) を Claude Code / Codex CLI に送信する
# tmux版: .config/tmux/scripts/claude-path-pick-broot.sh, codex-path-pick-broot.sh
#
# broot の from_shell verb は outcmd にシェルコマンドを書くだけで
# 本来は br 関数が eval する必要があるため、このスクリプトが同じ処理を行う
#
# path-pick-fzf.sh と同じ理由でagent判定を実行時に行い、
# Codex CLI には "@" prefixを付けずに送る。

set -euo pipefail

cd "$HERDR_ACTIVE_PANE_CWD"

CLAUDE_PATH_PICK_FILE=$(mktemp -t claude-path-pick.XXXXXX)
OUTCMD_FILE=$(mktemp -t broot-outcmd.XXXXXX)
export CLAUDE_PATH_PICK_FILE
trap 'rm -f "$CLAUDE_PATH_PICK_FILE" "$OUTCMD_FILE"' EXIT

broot --outcmd "$OUTCMD_FILE"

# outcmd を source して verb のシェルコマンドを実行
if [[ -s "$OUTCMD_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$OUTCMD_FILE"
fi

[[ ! -s "$CLAUDE_PATH_PICK_FILE" ]] && exit 0

is_codex=false
if herdr pane process-info --pane "$HERDR_ACTIVE_PANE_ID" |
  jq -e 'any(.result.process_info.foreground_processes[]?; .name == "codex")' >/dev/null 2>&1; then
  is_codex=true
fi

# 改行区切りで複数パスに対応 (単一パスでも 1 行として処理)
# 最終行が改行で終わらない場合にも読み取れるよう `|| [[ -n "$p" ]]` を付ける
payload=""
while IFS= read -r p || [[ -n "$p" ]]; do
  [[ -z "$p" ]] && continue
  if $is_codex; then
    case "$p" in
    "$PWD"/*) payload+="${p#"$PWD"/} " ;;
    "$PWD") payload+=". " ;;
    *) payload+="${p} " ;;
    esac
  else
    case "$p" in
    "$PWD"/*) payload+="@${p#"$PWD"/} " ;;
    "$PWD") payload+="@. " ;;
    *) payload+="@${p} " ;;
    esac
  fi
done <"$CLAUDE_PATH_PICK_FILE"

herdr pane send-text "$HERDR_ACTIVE_PANE_ID" "$payload"
