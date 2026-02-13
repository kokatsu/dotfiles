#!/bin/bash
# Claude Code用プロンプト編集スクリプト (tmux版)
# Alt-v でNeovimを起動し、編集後に内容をClaude Codeに送信する
# https://zenn.dev/shisashi/articles/0ba22e272d6f2f

# 一時ファイルを作成（.claude拡張子で専用設定を適用）
TMPFILE="/tmp/claude-prompt-$$.claude"

# Neovimでインサートモードで開始
nvim -c "startinsert" "$TMPFILE"

# 内容が存在する場合のみ送信
if [ -s "$TMPFILE" ]; then
    CONTENT=$(cat "$TMPFILE")

    # tmuxのpopupが閉じた後、元のペインに内容を送信
    # send-keysで文字を送信（-lでリテラル送信）
    tmux send-keys -l "$CONTENT"
fi

# 一時ファイルを削除
rm -f "$TMPFILE"
