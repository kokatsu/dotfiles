#!/usr/bin/env bash
# test-detect-hash-updates.sh — scripts/detect-hash-updates.sh を fixture で検証する。
# 実際の overlay を一時 Git リポジトリにコピーして base コミットを作り、作業ツリーを
# 書き換えてから detect を走らせ、出力の has_* / version_* / packages を照合する。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detect="$repo_root/scripts/detect-hash-updates.sh"

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

failures=0
pass() { echo "  PASS $1"; }
fail() {
  echo "  FAIL $1" >&2
  failures=$((failures + 1))
}

# GNU (Linux/CI) と BSD (macOS) の sed -i 互換ヘルパー
sedi() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# fixture リポジトリ: 実際の overlay / flake.nix / karabiner-config を base として commit
mkdir -p "$tmp/nix/overlays" "$tmp/karabiner-config"
cp "$repo_root"/nix/overlays/*.nix "$tmp/nix/overlays/"
cp "$repo_root/flake.nix" "$tmp/flake.nix"
cp "$repo_root/karabiner-config/deno.json" "$tmp/karabiner-config/deno.json"
: >"$tmp/karabiner-config/deno.lock"
git -C "$tmp" init -q -b main
git -C "$tmp" -c user.name=test -c user.email=test@example.com add -A
git -C "$tmp" -c user.name=test -c user.email=test@example.com commit -q -m base

run_detect() {
  (cd "$tmp" && bash "$detect" main)
}

reset_tree() {
  git -C "$tmp" checkout -q -- .
}

expect_line() {
  local label="$1" output="$2" line="$3"
  if grep -qxF "$line" <<<"$output"; then
    pass "$label: $line"
  else
    fail "$label: expected '$line' in:"$'\n'"$output"
  fi
}

expect_absent() {
  local label="$1" output="$2" pattern="$3"
  if grep -qE "$pattern" <<<"$output"; then
    fail "$label: '$pattern' should not appear in:"$'\n'"$output"
  else
    pass "$label: no $pattern"
  fi
}

vite_section='/vite-plus = _final: prev: let/,/^  };/'
vite_version=$(sed -n "${vite_section}{s/.*version = \"\([^\"]*\)\".*/\1/p;}" "$tmp/nix/overlays/npm-packages.nix" | head -1)
[[ -n "$vite_version" ]] || {
  echo "could not read the vite-plus version from the fixture" >&2
  exit 1
}

# 1. 変更なし
out=$(run_detect)
expect_absent "no change" "$out" '^has_'
expect_line "no change" "$out" "packages="

# 2. vite-plus の version だけ上げる (同じファイルの textlint は反応しない)
sedi "${vite_section}{s/version = \"${vite_version}\"/version = \"9.9.9\"/;}" "$tmp/nix/overlays/npm-packages.nix"
out=$(run_detect)
expect_line "vite-plus bump" "$out" "has_vite_plus=true"
expect_line "vite-plus bump" "$out" "version_vite_plus=9.9.9"
expect_line "vite-plus bump" "$out" "packages=vite-plus 9.9.9"
expect_absent "vite-plus bump" "$out" '^has_textlint'
reset_tree

# 3. コメントだけの変更 (パッケージ名を含む) では反応しない
printf '\n# touched: vite-plus textlint-rule-preset-ai-writing codex claude-code\n' >>"$tmp/nix/overlays/npm-packages.nix"
printf '\n# touched: codex claude-code\n' >>"$tmp/nix/overlays/binary-releases.nix"
out=$(run_detect)
expect_absent "comment-only" "$out" '^has_'
reset_tree

# 4. karabiner の deno.lock と flake.nix
printf 'x\n' >>"$tmp/karabiner-config/deno.lock"
printf '\n# touched\n' >>"$tmp/flake.nix"
out=$(run_detect)
expect_line "lock/flake" "$out" "has_karabinerts_deno_lock=true"
expect_line "lock/flake" "$out" "has_flake_nix=true"
expect_absent "lock/flake" "$out" '^has_(vite|textlint|codex|claude|cssmodules|x_api)'
reset_tree

# 5. 不正な version は fail closed
sedi "${vite_section}{s/version = \"${vite_version}\"/version = \"9.9.9; rm -rf \/\"/;}" "$tmp/nix/overlays/npm-packages.nix"
if run_detect >/dev/null 2>&1; then
  fail "invalid version should make detect exit non-zero"
else
  pass "invalid version makes detect exit non-zero"
fi
reset_tree

if [[ $failures -gt 0 ]]; then
  echo "detect-hash-updates tests: $failures failure(s)" >&2
  exit 1
fi
echo "detect-hash-updates tests passed"
