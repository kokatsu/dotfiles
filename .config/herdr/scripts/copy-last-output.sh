#!/bin/bash
# 現在のペインで直前に実行したコマンドと出力をクリップボードへコピーする。
# starship プロンプトの 1 行目 (directory モジュールの U+E0BA で始まる) を区切りに、
# 最後から 2 つ目のプロンプトから最後のプロンプトの手前までを取り出す。
# フォアグラウンドが psql のときは psql のプロンプトを区切りにし、
# 貼り付けてそのまま実行できるよう出力を SQL コメントにする。

set -euo pipefail

active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}
# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if ! screen=$("$herdr_bin" pane read "$active_pane_id" --source recent-unwrapped --lines 1000 --format text); then
  notify "ペインの読み取りに失敗しました"
  exit 1
fi

status=0
if "$herdr_bin" pane process-info --pane "$active_pane_id" 2>/dev/null |
  jq -e 'any(.result.process_info.foreground_processes[]; .name == "psql")' >/dev/null; then
  lang="sql"
  # プロンプトの形は nix/home/programs/psql.nix の PROMPT1 / PROMPT2 に合わせている
  out=$(perl -CSD -0777 -ne '
    # pane read は行末の空白を削るので、入力待ちのプロンプトは末尾の空白を持たない
    my $p1 = qr/^\S* \[\d\d:\d\d:\d\d\] [=^!][#>](?: |$)/;
    my @lines = split /\n/;
    my @h = grep { $lines[$_] =~ $p1 } 0 .. $#lines;
    exit 3 if @h < 2;
    my @block = @lines[ $h[-2] .. $h[-1] - 1 ];
    $block[0] =~ s/$p1//;
    # 貼り付けた複数行には PROMPT2 が付かないので、クエリの終わりは psql が
    # 送信を始める行で判断する。引用符・E 文字列・ドル引用・コメントの外にある ; か
    # メタコマンドの行で、DO $$ ... $$ の中の ; では終わらない
    my ($quote, $esc, $depth, $done, $i) = (undef, 0, 0, 0, 0);
    while ($i < @block && !$done) {
      $block[$i] =~ s/^\[more\] \S > // if $i > 0;
      my $l = $block[ $i++ ];
      pos($l) = 0;
      while (pos($l) < length $l) {
        if ($depth) {
          if    ($l =~ /\G\/\*/gc) { $depth++ }
          elsif ($l =~ /\G\*\//gc) { $depth-- }
          else                     { $l =~ /\G./gcs }
        }
        elsif (defined $quote) {
          if    ($esc && $l =~ /\G(?:\\.|\x27\x27)/gcs) { }
          elsif ($l =~ /\G\Q$quote\E/gc)               { undef $quote }
          else                                         { $l =~ /\G./gcs }
        }
        elsif ($l =~ /\G--/gc)                              { last }
        elsif ($l =~ /\G\/\*/gc)                            { $depth = 1 }
        elsif ($l =~ /\G(?<![\w\$])[Ee]\x27/gc)             { ($quote, $esc) = ("\x27", 1) }
        elsif ($l =~ /\G(\x27|"|\$(?:[A-Za-z_]\w*)?\$)/gc) { ($quote, $esc) = ($1, 0) }
        elsif ($l =~ /\G(?:;|\\[a-zA-Z?!])/gc)              { $done = 1; last }
        else                                                { $l =~ /\G./gcs }
      }
    }
    my @output = @block[ $i .. $#block ];
    s/\s+$// for @output;
    pop @output while @output && $output[-1] eq "";
    print join("\n", @block[ 0 .. $i - 1 ], map { $_ eq "" ? "--" : "-- $_" } @output), "\n";
  ' <<<"$screen") || status=$?
else
  lang="sh"
  # コマンド行の battery と character のグリフは貼り付け先で意味を持たないので $ に置き換える。
  # 改行で終わらない出力には zsh の PROMPT_SP が % を付け、starship の add_newline の空行も入らない
  out=$(perl -CSD -0777 -ne '
    my @lines = split /\n/;
    my @h = grep { $lines[$_] =~ /^\x{E0BA}/ } 0 .. $#lines;
    exit 3 if @h < 2;
    my @block = @lines[ $h[-2] + 1 .. $h[-1] - 1 ];
    exit 0 unless @block;
    $block[0] =~ s/^.*?[\x{F00C}\x{F00D}] ?/\$ /;
    my $blank = 0;
    while (@block && $block[-1] =~ /^\s*$/) { pop @block; $blank = 1 }
    $block[-1] =~ s/%$// if @block && !$blank;
    print join("\n", @block), "\n" if @block;
  ' <<<"$screen") || status=$?
fi

# pane read は --lines を増やしても直近 1000 行ほどしか返さないので、長い出力の後は
# 直前のプロンプトが範囲外になる
if ((status == 3)); then
  notify "直前のコマンドが読み取れる範囲 (直近約 1000 行) にありません"
  exit 0
fi

if [[ -z "$out" ]]; then
  notify "コピーできるコマンドの出力がありません"
  exit 0
fi

fence='```'
while [[ $out == *"$fence"* ]]; do
  fence+='`'
done
out="$fence$lang"$'\n'"$out"$'\n'"$fence"

if [[ $(uname -s) == Darwin ]]; then
  printf '%s' "$out" | pbcopy
else
  printf '%s' "$out" | xsel -ib
fi
notify "直前のコマンドと出力をコピーしました"
