#!/usr/bin/env bash
# check-regex-dialect.sh — banned-commands.json の POSIX ERE を Go の正規表現へ
# 変換したときの差を、実行中の OS と locale で測る。
#
# banned-commands.json の正本方言は POSIX ERE で、フック (claude-bash-guard) は
# rules.Convert() を通してからコンパイルする。ここで確かめるのはその変換が取りこぼしを生まないこと
# である。locale を変えると POSIX 側の文字クラスが変わるので、対象環境ごとに
# 走らせる。macOS の BSD libc は LANG=en_US.UTF-8 で通ることを確かめてある。
#
# 受け入れ条件は 4 つあり、どれか 1 つでも崩れたら exit 1 で落ちる。
#
#   1. POSIX [[:space:]] のみに一致する符号位置が空であること
#   2. A-Za-z0-9 が POSIX [[:alnum:]] の部分集合であること
#   3. jq (Oniguruma) の [[:space:]] をフックの JQSpaceClass が包含すること
#   4. corpus の判定が両方言で一致すること
#
# 1 と 2 は「Go 側が POSIX 側を包含する」ことの確認である。包含して
# いる限り差は過剰ブロックにしか出ず、禁止ルールでは fail-safe になる。逆向き
# の差は取りこぼしなので許容しない。corpus は特定の入力しか見ないので、一般の
# 場合を保証するのはこの 2 つだけである。
#
# 3 は sSplit と ansiDecode のための別の包含関係である。この 2 つは jq の
# プログラムから書き写しており、jq は Oniguruma なので集合が POSIX とも
# Go とも違う。
#
# 4 は変換器そのものの検査である。1 から 3 が成り立っていても rules.Convert() が
# 壊れれば判定は変わる。corpus は判定が一致する入力だけで構成してあるため、
# 差分はすべて異常として扱う。過剰ブロック側の入力を corpus へ入れるなら、
# 行ごとの期待値を持たせてから入れる。
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
rules="$repo_root/tools/claude-bash-guard/rules/banned-commands.json"
# go run はモジュールのディレクトリで走らせる。補助ツールは標準ライブラリだけを
# 使うので、依存の取得は起きない。
helper() { (cd "$repo_root/tools/claude-bash-guard" && go run ./cmd/regex-dialect "$@"); }
corpus="$repo_root/scripts/regex-dialect-corpus.txt"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failed=0

printf 'locale: LANG=%s LC_ALL=%s\n' "${LANG:-unset}" "${LC_ALL:-unset}"
printf 'bash:   %s\n\n' "$BASH_VERSION"

# BMP を走査して、POSIX 側の文字クラスに一致する符号位置を $1 へ書き出す。
# printf -v はコマンド置換を経由しないので、U+000A が末尾改行として落ちない。
# $(printf '\n') で作ると改行だけが集合から抜け、差が 1 個多く出る。
scan_posix_class() {
  local class=$1 cp escape ch
  for ((cp = 1; cp <= 0xffff; cp++)); do
    ((cp < 0xd800 || cp > 0xdfff)) || continue # 単独のサロゲートは UTF-8 にならない
    printf -v escape '\\u%04x' "$cp"
    # shellcheck disable=SC2059  # $escape を書式として解釈させるのが目的
    printf -v ch "$escape"
    if [[ $ch =~ ^[[:$class:]]$ ]]; then
      printf 'U+%04X\n' "$cp"
    fi
  done
}

# --- 1. whitespace: POSIX [[:space:]] と Go 側の SpaceClass ---
scan_posix_class space | sort >"$work/posix-space.txt"
helper space-set | sort >"$work/go-space.txt"

comm -23 "$work/posix-space.txt" "$work/go-space.txt" >"$work/space-posix-only.txt"
comm -13 "$work/posix-space.txt" "$work/go-space.txt" >"$work/space-go-only.txt"

printf '[whitespace class]\n'
printf '  POSIX [[:space:]]: %s code points\n' "$(wc -l <"$work/posix-space.txt")"
printf '  Go SpaceClass:      %s code points\n' "$(wc -l <"$work/go-space.txt")"
printf '  Go のみ (過剰ブロック、許容): %s\n' "$(tr '\n' ' ' <"$work/space-go-only.txt")"
printf '  POSIX のみ (取りこぼし、不可):        %s\n\n' "$(tr '\n' ' ' <"$work/space-posix-only.txt")"

if [[ -s $work/space-posix-only.txt ]]; then
  echo 'FAIL: POSIX [[:space:]] のみに一致する符号位置がある。変換すると取りこぼしになる。' >&2
  failed=1
fi

# --- 2. alnum: A-Za-z0-9 が POSIX [[:alnum:]] の部分集合か ---
# ルールでの使われ方は否定形 [^[:alnum:]_] なので、包含の向きが逆転する。
# A-Za-z0-9 が部分集合である限り [^A-Za-z0-9_] は [^[:alnum:]_] を包含し、
# 差は過剰ブロック側に出る。
# 走査するのは A-Za-z0-9 の 62 文字だけでよい。POSIX 側が非 ASCII をいくつ
# 含むかは条件に関係せず、BMP 全域を舐めると 5 秒かかる。
for cp in {48..57} {65..90} {97..122}; do
  printf -v escape '\\u%04x' "$cp"
  # shellcheck disable=SC2059  # $escape を書式として解釈させるのが目的
  printf -v ch "$escape"
  [[ $ch =~ ^[[:alnum:]]$ ]] || printf 'U+%04X\n' "$cp"
done >"$work/alnum-ascii-only.txt"

printf '[alnum class]\n'
printf '  A-Za-z0-9 のうち POSIX [[:alnum:]] に含まれないもの (不可): %s\n\n' \
  "$(tr '\n' ' ' <"$work/alnum-ascii-only.txt")"

if [[ -s $work/alnum-ascii-only.txt ]]; then
  echo 'FAIL: A-Za-z0-9 が POSIX [[:alnum:]] の部分集合になっていない。否定形の包含が逆転する。' >&2
  failed=1
fi

# --- 3. jq (Oniguruma) の [[:space:]] を JQSpaceClass が包含するか ---
# banned-commands.json と違い、claude-bash-guard の sSplit は
# jq のプログラムから書き写した。jq は Oniguruma なので集合が POSIX とも
# Go とも違い、jq だけが U+0085 に一致する。
# フック側の JQSpaceClass (SpaceClass と U+0085) がこの集合を包含することをここで確かめる。
jq -nr 'range(1;65536) | select(. < 55296 or . > 57343)
        | select(([.] | implode) | test("[[:space:]]")) | .' |
  awk '{printf "U+%04X\n", $1}' | sort >"$work/jq-space.txt"

helper jq-space-set | sort >"$work/hook-space.txt"

comm -23 "$work/jq-space.txt" "$work/hook-space.txt" >"$work/jq-only.txt"

printf '[jq whitespace class vs the hook JQSpaceClass]\n'
printf '  jq [[:space:]]: %s code points\n' "$(wc -l <"$work/jq-space.txt")"
printf '  hook JQSpaceClass: %s code points\n' "$(wc -l <"$work/hook-space.txt")"
printf '  jq のみ (取りこぼし、不可): %s\n\n' "$(tr '\n' ' ' <"$work/jq-only.txt")"

if [[ -s $work/jq-only.txt ]]; then
  echo 'FAIL: jq の [[:space:]] のみに一致する符号位置がある。env -S の区切りを取りこぼす。' >&2
  failed=1
fi

# --- 4. 実パターンを corpus で突き合わせる ---
patterns=()
while IFS= read -r line; do patterns+=("$line"); done < <(jq -r '.[].pattern' "$rules")

while IFS= read -r line; do
  [[ -n $line ]] || continue
  verdict=allow
  for pattern in "${patterns[@]}"; do
    if [[ $line =~ $pattern ]]; then
      verdict=BLOCK
      break
    fi
  done
  printf '%s\t%s\n' "$verdict" "$line"
done <"$corpus" >"$work/posix-verdicts.txt"

helper match-corpus <"$corpus" >"$work/go-verdicts.txt"

printf '[corpus verdicts]\n'
if diff -u "$work/posix-verdicts.txt" "$work/go-verdicts.txt" >"$work/corpus.diff"; then
  printf '  %s 行すべて一致\n\n' "$(wc -l <"$work/posix-verdicts.txt")"
else
  printf '  差分あり:\n'
  sed 's/^/    /' "$work/corpus.diff"
  printf '\n'
  echo 'FAIL: corpus の判定が両方言で食い違う。変換器が壊れている。' >&2
  failed=1
fi

if ((failed)); then
  exit 1
fi

echo 'OK: 包含は保たれ、corpus の判定も一致する。'
