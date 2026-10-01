#!/bin/bash
# パス選択スクリプト (broot版, herdr版)
# Alt-g で broot を起動。選択方法:
#   - ファイル上で Enter: 単一ファイル選択
#   - Ctrl+p: カレント選択 (ファイル/ディレクトリ両対応) を単一で確定
#   - Space: staging 切替 (複数選択)
#   - Ctrl+a: staged をまとめて確定
# 選択したパス (単一/複数) を起動元ペイン (Claude Code / Codex CLI / シェル) に送信する
#
# broot の from_shell verb は outcmd にシェルコマンドを書くだけで
# 本来は br 関数が eval する必要があるため、このスクリプトが同じ処理を行う

set -euo pipefail

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

cd "${HERDR_ACTIVE_PANE_CWD:?HERDR_ACTIVE_PANE_CWD is not set}"

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

send_paths "$active_pane_id" <"$CLAUDE_PATH_PICK_FILE"
