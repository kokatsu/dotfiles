#!/bin/bash
# 現在のペインで直前に実行したコマンドと出力をクリップボードへコピーする。
# starship プロンプトの 1 行目 (directory モジュールの U+E0BA で始まる) を区切りに、
# 最後から 2 つ目のプロンプトから最後のプロンプトの手前までを取り出す。

set -euo pipefail

active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}
# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if ! screen=$("$herdr_bin" pane read "$active_pane_id" --source recent-unwrapped --lines 1000 --format text); then
  notify "ペインの読み取りに失敗しました"
  exit 1
fi

# コマンド行の battery と character のグリフは貼り付け先で意味を持たないので $ に置き換える。
# 改行で終わらない出力には zsh の PROMPT_SP が % を付け、starship の add_newline の空行も入らない
out=$(perl -CSD -0777 -ne '
  my @lines = split /\n/;
  my @h = grep { $lines[$_] =~ /^\x{E0BA}/ } 0 .. $#lines;
  exit 0 if @h < 2;
  my @block = @lines[ $h[-2] + 1 .. $h[-1] - 1 ];
  exit 0 unless @block;
  $block[0] =~ s/^.*?[\x{F00C}\x{F00D}] ?/\$ /;
  my $blank = 0;
  while (@block && $block[-1] =~ /^\s*$/) { pop @block; $blank = 1 }
  $block[-1] =~ s/%$// if @block && !$blank;
  print join("\n", @block), "\n" if @block;
' <<<"$screen")

if [[ -z "$out" ]]; then
  notify "コピーできるコマンドの出力がありません"
  exit 0
fi

if [[ $(uname -s) == Darwin ]]; then
  printf '%s' "$out" | pbcopy
else
  printf '%s' "$out" | xsel -ib
fi
notify "直前のコマンドと出力をコピーしました"
