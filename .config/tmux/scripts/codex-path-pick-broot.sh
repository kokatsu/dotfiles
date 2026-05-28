#!/bin/bash
# Codex CLI用パス選択スクリプト (broot版)
# Alt-g で broot を起動。選択方法:
#   - ファイル上で Enter: 単一ファイル選択
#   - Ctrl+p: カレント選択 (ファイル/ディレクトリ両対応) を単一で確定
#   - Space: staging 切替 (複数選択)
#   - Ctrl+a: staged をまとめて確定
# 選択したパス (単一/複数) をスペース区切りで Codex CLI に送信する
#
# broot の from_shell verb は outcmd にシェルコマンドを書くだけで
# 本来は br 関数が eval する必要があるため、このスクリプトが同じ処理を行う
#
# claude-path-pick-broot.sh との違い:
#   Codex CLI は入力欄で "@" を打つと内蔵 fuzzy picker が開く仕様のため、
#   "@" prefix を付けずに相対パス文字列だけを送る。Codex エージェントは
#   パスらしき token を認識して自律的に Read する。
#   broot.nix の verb は $CLAUDE_PATH_PICK_FILE を共通の受け渡しファイルとして
#   再利用する (変数名は Claude 由来だが Codex とも共用)。

set -euo pipefail

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

# 改行区切りで複数パスに対応 (単一パスでも 1 行として処理)
# 最終行が改行で終わらない場合にも読み取れるよう `|| [[ -n "$p" ]]` を付ける
# claude 版と違い "@" は付けない
payload=""
while IFS= read -r p || [[ -n "$p" ]]; do
  [[ -z "$p" ]] && continue
  case "$p" in
  "$PWD"/*) payload+="${p#"$PWD"/} " ;;
  "$PWD") payload+=". " ;;
  *) payload+="${p} " ;;
  esac
done <"$CLAUDE_PATH_PICK_FILE"

tmux send-keys -l "$payload"
