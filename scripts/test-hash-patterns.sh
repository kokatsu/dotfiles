#!/usr/bin/env bash
# test-hash-patterns.sh — pr.yml の hash 更新 / version 検出パターンが overlay の構造に
# マッチし続けるか検証する。各テストは workflow が実際に使う sed アンカー・grep を
# そのまま再現するので、overlay 側がドリフトすると workflow が壊れる前にここで落ちる。
#
#   - hashSource を持たない mkBinaryRelease パッケージは自動発見し、汎用 update が使う
#     「^  <pkg> = mkBinaryRelease のセクション・extract_ver・per-platform hash sed」を検証。
#     手動リスト不要なので新しい binary ツールを足してもここは不変。
#   - hashSource を持つ binary (claude-code/codex) と非 mkBinaryRelease の bespoke は、
#     update sed アンカーが個別なので BESPOKE テーブルに明示し、アンカー・hash 種別に加えて
#     detect の version 抽出 (grep -A N "# Renovate:..." → version) も workflow と同形で検証する。
#   - 追加忘れ防止に、hashSource 付き binary と全 _final: prev: セクションが BESPOKE に
#     含まれているかを照合する。

set -euo pipefail

OVERLAY_DIR="${1:-nix/overlays}"
BINARY="$OVERLAY_DIR/binary-releases.nix"
ERRORS=0
TESTS=0

# Colors (CI でも見やすく)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
  TESTS=$((TESTS + 1))
  printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
  TESTS=$((TESTS + 1))
  ERRORS=$((ERRORS + 1))
  printf "${RED}  FAIL${NC} %s\n" "$1"
}

# GNU (Linux/CI) と BSD (macOS) の sed -i 互換ヘルパー
sedi() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# pr.yml の汎用 update が使うのと同一の version 抽出 (prefetch binary 用)
extract_ver() {
  sed -n "/^  $2 = mkBinaryRelease/,/^  };/{s/.*version = \"\([^\"]*\)\".*/\1/p;}" "$1" | head -1
}

# pr.yml の detect が使うのと同形の version 抽出 (bespoke 用)。
# $2=grep -A の行数, $3=Renovate コメントの grep パターン。コメントから N 行以内に
# version = "..." が無ければ空を返す (detect が空 version を出す状況を再現)。
extract_renovate_ver() {
  grep -A "$2" "$3" "$1" 2>/dev/null | sed -n 's/.*version = "\([^"]*\)".*/\1/p' | head -1 || true
}

# セクション ($3=開始パターン, workflow の sed アンカーと同一) 内の hash 行 ($4=正規表現) を
# DUMMY 化し、反映を確認する。pr.yml の hash sed と同じ /start/,/^  };/{s|...|...|} 形。
check_section_sed() {
  local label="$1" file="$2" start="$3" line_pat="$4"
  local tmp
  tmp=$(mktemp)
  cp "$file" "$tmp"
  sedi "/$start/,/^  };/{s|$line_pat|XXXDUMMYXXX|;}" "$tmp"
  if grep -q "XXXDUMMYXXX" "$tmp"; then
    pass "$label: sed round-trip"
  else
    fail "$label: sed had NO EFFECT (pattern drift?)"
  fi
  rm -f "$tmp"
}

# attrset ブロックから代入の左辺キー ("key" = ...) だけを取り出す (値は拾わない)
extract_attr_keys() {
  grep -oE '"[a-z0-9_-]+"[[:space:]]*=' | sed -E 's/"([a-z0-9_-]+)".*/\1/'
}

# binary-releases.nix の共有 platformMap 変数を一度だけ解決しておく。
# 各パッケージの「期待プラットフォーム集合」を hashes 行ではなく platformMap から導くことで、
# あるプラットフォームの hash 行が削除/改名/形式崩れしたケースを取りこぼさず検出する
# (workflow は platformMap (= manifest) のキーで update/verify を回すため、それと一致させる)。
APPLE_KEYS=$(sed -n '/^  appleGnuPlatformMap = {/,/^  };/p' "$BINARY" | extract_attr_keys || true)
# currentAppleGnuPlatformMap = builtins.removeAttrs appleGnuPlatformMap ["x86_64-darwin"]; の除外リスト
CURRENT_REMOVED=$(grep -E '^  currentAppleGnuPlatformMap = ' "$BINARY" | grep -oE '\[[^]]*\]' | grep -oE '"[a-z0-9_-]+"' | sed -E 's/"([a-z0-9_-]+)"/\1/' || true)
APPLE_CURRENT_KEYS=$(comm -23 <(printf '%s\n' "$APPLE_KEYS" | sort) <(printf '%s\n' "$CURRENT_REMOVED" | sort))

# セクション ($3=開始パターン, $2=ファイル) の platformMap が宣言する「期待プラットフォーム集合」を返す。
# インライン { ... } / appleGnuPlatformMap / currentAppleGnuPlatformMap を解決する。
# 未知の参照形式は __UNRESOLVED__ を返し、呼び出し側で loud fail させる (silent pass を避ける)。
expected_platforms() {
  local file="$1" start="$2" section pm_line
  section=$(sed -n "/$start/,/^  };/p" "$file")
  pm_line=$(printf '%s\n' "$section" | grep -E 'platformMap = ' | head -1 || true)
  if printf '%s\n' "$pm_line" | grep -q 'platformMap = {'; then
    printf '%s\n' "$section" | sed -n '/platformMap = {/,/};/p' | extract_attr_keys
  elif printf '%s\n' "$pm_line" | grep -q 'platformMap = currentAppleGnuPlatformMap'; then
    printf '%s\n' "$APPLE_CURRENT_KEYS"
  elif printf '%s\n' "$pm_line" | grep -q 'platformMap = appleGnuPlatformMap'; then
    printf '%s\n' "$APPLE_KEYS"
  else
    echo "__UNRESOLVED__"
  fi
}

# セクション ($3=開始パターン) の per-platform hash 行を sed で個別にラウンドトリップ検証する。
# 期待プラットフォームは platformMap (expected_platforms) から導くので、hash 行が
# 削除/改名/sha256- から逸脱した場合に round-trip 失敗として確実に検出できる。
check_platform_hashes() {
  local label="$1" file="$2" start="$3"
  local keys key
  keys=$(expected_platforms "$file" "$start")
  if [ -z "$keys" ]; then
    fail "$label: no platformMap keys found"
    return
  fi
  if printf '%s\n' "$keys" | grep -q '__UNRESOLVED__'; then
    fail "$label: unresolvable platformMap reference (add it to expected_platforms)"
    return
  fi
  for key in $keys; do
    check_section_sed "$label $key" "$file" "$start" "\"${key}\" = \"sha256-[^\"]*\""
  done
}

# ============================================================================
# bespoke テーブル (update sed アンカーが個別なパッケージ)
# 形式: "name|file|update_anchor|hash_kind|grep_after|renovate_grep"
#   update_anchor : pr.yml の sed が使うのと同一のセクション開始パターン
#   hash_kind     : platform | single | npm | both | vendor
#   grep_after    : detect の grep -A N の N
#   renovate_grep : detect の grep パターン ("# Renovate:..." )
# ============================================================================
BESPOKE=(
  'codex|binary-releases.nix|codex = mkBinaryRelease|platform|30|# Renovate:.*depName=openai/codex'
  'claude-code|binary-releases.nix|# Claude Code - agentic coding tool|platform|20|# Renovate:.*depName=claude-code'
  'cssmodules-language-server|source-builds.nix|cssmodules-language-server = _final: prev: {|both|20|# Renovate:.*depName=.*cssmodules-language-server'
  'x-api-playground|source-builds.nix|x-api-playground = _final: prev: {|vendor|20|# Renovate:.*depName=.*playground'
  'vite-plus|npm-packages.nix|vite-plus = _final: prev: let|npm|20|# Renovate:.*depName=vite-plus'
  'textlint-rule-preset-ai-writing|npm-packages.nix|textlint-rule-preset-ai-writing = _final: prev: let|npm|20|# Renovate:.*depName=@textlint-ja/textlint-rule-preset-ai-writing'
  'win32yank|standalone.nix|win32yank = _final: prev:|single|20|# Renovate:.*depName=.*win32yank'
)

bespoke_has() {
  local name="$1" entry
  for entry in "${BESPOKE[@]}"; do
    [ "${entry%%|*}" = "$name" ] && return 0
  done
  return 1
}

# ============================================================================
# 1. binary-releases.nix の mkBinaryRelease パッケージ (自動発見)
#    hashSource を持つもの (claude-code/codex) は bespoke なので generic テストから除外する。
# ============================================================================
echo "=== prefetch mkBinaryRelease packages (auto-discovered) ==="
echo ""

BIN_PKGS=()
while IFS= read -r p; do
  BIN_PKGS+=("$p")
done < <(grep -oE '^  [A-Za-z0-9_-]+ = mkBinaryRelease' "$BINARY" | sed -E 's/^  ([A-Za-z0-9_-]+) .*/\1/')

if [ "${#BIN_PKGS[@]}" -eq 0 ]; then
  fail "no mkBinaryRelease packages discovered (regex drift?)"
fi

# discovery 健全性: anchor (^  X = mkBinaryRelease) で発見した件数が、formatting に依存しない
# mkBinaryRelease の関数適用箇所 (... mkBinaryRelease ... {、コメントや inherit は除外) の数と
# 一致すること。anchor がドリフトして 1 つでも発見漏れすると、テストが静かに件数を減らして
# 通過するのではなくここで loud fail する。
USAGES=$(grep -cE 'mkBinaryRelease.*[{]' "$BINARY" || true)
if [ "${#BIN_PKGS[@]}" -ne "$USAGES" ]; then
  fail "discovered ${#BIN_PKGS[@]} packages via anchor but found $USAGES mkBinaryRelease usages — a section opening line may have drifted"
fi

for pkg in "${BIN_PKGS[@]}"; do
  section=$(sed -n "/^  ${pkg} = mkBinaryRelease/,/^  };/p" "$BINARY")

  # hashSource が prefetch 以外 (manifest/sha256sums) なら bespoke。値で判定するので、
  # 既定値の hashSource = "prefetch" を明示しても generic として扱える (mkBinaryRelease の
  # 既定も "prefetch"、pr.yml も manifest 値が prefetch のものを汎用ループで処理する)。
  hs=$(printf '%s\n' "$section" | sed -n 's/.*hashSource = "\([^"]*\)".*/\1/p' | head -1)
  if [ -n "$hs" ] && [ "$hs" != "prefetch" ]; then
    if bespoke_has "$pkg"; then
      pass "[$pkg] non-prefetch hashSource ($hs) is covered by BESPOKE"
    else
      fail "[$pkg] has hashSource=$hs but no BESPOKE entry — add it"
    fi
    continue
  fi

  echo "[$pkg]"

  cnt=$(grep -cE "^  ${pkg} = mkBinaryRelease" "$BINARY" || true)
  if [ "$cnt" -eq 1 ]; then
    pass "section anchor matches once"
  else
    fail "section anchor matches $cnt times (expected 1)"
  fi

  ver=$(extract_ver "$BINARY" "$pkg")
  if [ -n "$ver" ]; then
    pass "extract_ver -> $ver"
  else
    fail "extract_ver returned empty"
  fi

  check_platform_hashes "  hash" "$BINARY" "^  ${pkg} = mkBinaryRelease"
  echo ""
done

# ============================================================================
# 2. bespoke パッケージ (workflow の exact アンカー / version grep を再現)
# ============================================================================
echo "=== bespoke packages (exact workflow anchors) ==="
echo ""

for entry in "${BESPOKE[@]}"; do
  IFS='|' read -r name file anchor kind grep_after renovate_grep <<<"$entry"
  filepath="$OVERLAY_DIR/$file"
  echo "[$name] ($file)"

  # update sed アンカーが一意に存在する (fixed-string で { や let を literal 扱い)
  cnt=$(grep -cF "$anchor" "$filepath" || true)
  if [ "$cnt" -eq 1 ]; then
    pass "update anchor matches once"
  else
    fail "update anchor matches $cnt times (expected 1): '$anchor'"
  fi

  # detect と同形の version 抽出が値を返す (Renovate コメント存在 + N 行以内に version)
  ver=$(extract_renovate_ver "$filepath" "$grep_after" "$renovate_grep")
  if [ -n "$ver" ]; then
    pass "renovate version extract -> $ver"
  else
    fail "renovate version extract returned empty (comment drift or >$grep_after lines to version)"
  fi

  # hash sed のラウンドトリップ (種別ごと)。パターンは pr.yml の sed と末尾 ; の有無まで
  # 一致させる: single/vendor の hash・vendorHash は ";" 込み、npmDepsHash・platform は ; なし。
  case "$kind" in
  platform)
    check_platform_hashes "  hash" "$filepath" "$anchor"
    ;;
  single)
    check_section_sed "hash" "$filepath" "$anchor" 'hash = "sha256-[^"]*";'
    ;;
  npm)
    check_section_sed "npmDepsHash" "$filepath" "$anchor" 'npmDepsHash = "sha256-[^"]*"'
    ;;
  both)
    check_section_sed "hash" "$filepath" "$anchor" 'hash = "sha256-[^"]*";'
    check_section_sed "npmDepsHash" "$filepath" "$anchor" 'npmDepsHash = "sha256-[^"]*"'
    ;;
  vendor)
    check_section_sed "hash" "$filepath" "$anchor" 'hash = "sha256-[^"]*";'
    check_section_sed "vendorHash" "$filepath" "$anchor" 'vendorHash = "sha256-[^"]*";'
    ;;
  esac
  echo ""
done

# ============================================================================
# 3. 追加忘れ検出: source-builds / npm / standalone の _final: prev: セクションが
#    全て BESPOKE に登録されているか照合する
# ============================================================================
echo "=== bespoke coverage (no missing _final: prev: sections) ==="
for file in source-builds.nix npm-packages.nix standalone.nix; do
  filepath="$OVERLAY_DIR/$file"
  [ -f "$filepath" ] || continue
  while IFS= read -r sec; do
    if bespoke_has "$sec"; then
      pass "$sec ($file) covered"
    else
      fail "$sec ($file) has no BESPOKE entry — add it"
    fi
  done < <(grep -oE '^  [A-Za-z0-9_-]+ = _final: prev:' "$filepath" | sed -E 's/^  ([A-Za-z0-9_-]+) .*/\1/')
done
echo ""

echo "=== Results: $TESTS tests, $ERRORS failures ==="
if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "ERROR: $ERRORS test(s) failed. The hash-update / version-detection patterns in"
  echo "       pr.yml no longer match the overlay structure. Fix the patterns or overlay."
  exit 1
fi
echo "All tests passed."
