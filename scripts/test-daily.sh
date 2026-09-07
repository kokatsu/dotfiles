#!/usr/bin/env bash
# test-daily.sh — bin/daily の --offset と出力契約を検証する。
# 一時 Git リポジトリを作り、stdout にパスだけが出ること、ファイル名と見出しが
# 一致すること、--offset が日付をずらすこと、不正な値で失敗することを見る。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
daily="$repo_root/bin/daily"

# macOS の /var は /private/var への symlink で、git rev-parse は実パスを返すため揃える
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q

failures=0
pass() { echo "  PASS $1"; }
fail() {
  echo "  FAIL $1" >&2
  failures=$((failures + 1))
}

run_daily() {
  (cd "$tmp" && "$daily" --no-edit "$@" 2>/dev/null)
}

# パスの形式と見出し
path=$(run_daily)
base=$(basename "$path" .md)
# bash の =~ は後方参照を持たないので、ディレクトリと日付を別々に照合する
if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ &&
  "$path" == "$tmp/.kokatsu/daily/${base:0:4}/${base:5:2}/$base.md" ]]; then
  pass "path follows .kokatsu/daily/YYYY/MM/YYYY-MM-DD.md"
else
  fail "unexpected path: $path"
fi
if [[ "$(head -n 1 "$path")" == "# $base" ]]; then
  pass "heading matches the file name"
else
  fail "heading does not match: $(head -n 1 "$path")"
fi

# --offset 0 は既定と同じ
if [[ "$(run_daily --offset 0)" == "$path" ]]; then
  pass "--offset 0 equals the default"
else
  fail "--offset 0 differs from the default"
fi

# 前後 1 日は別ファイルで、日付順に並ぶ
yesterday=$(basename "$(run_daily --offset -1)" .md)
tomorrow=$(basename "$(run_daily --offset=+1)" .md)
if [[ "$yesterday" < "$base" && "$base" < "$tomorrow" ]]; then
  pass "--offset -1 / +1 move one day backward / forward ($yesterday < $base < $tomorrow)"
else
  fail "offset ordering broken: $yesterday $base $tomorrow"
fi

# 既存ファイルを切り詰めない
printf 'body\n' >>"$path"
run_daily >/dev/null
if [[ "$(wc -l <"$path" | tr -d ' ')" == 2 ]]; then
  pass "existing diary is not truncated"
else
  fail "existing diary was rewritten"
fi

# 不正な offset は失敗する
if run_daily --offset x >/dev/null; then
  fail "--offset x should fail"
else
  pass "--offset x fails"
fi

if [[ $failures -gt 0 ]]; then
  echo "daily tests: $failures failure(s)" >&2
  exit 1
fi
echo "daily tests passed"
