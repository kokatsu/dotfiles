#!/usr/bin/env bash
# test-hash-patterns.sh — update-nix-hashes.yml の sed パターンが overlay ファイルに正しくマッチするか検証する
#
# 検証項目:
#   1. 各パッケージの sed セクション開始パターンがファイル内でマッチすること
#   2. セクション内にハッシュパターン（sha256-...）が存在すること
#   3. Renovate コメントからバージョンが抽出できること
#   4. ダミー値での sed 置換が実際に反映されること

set -euo pipefail

OVERLAY_DIR="${1:-nix/overlays}"
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

# --- パッケージ定義 ---
# 形式: "name|file|sed_start_pattern|renovate_pattern|hash_type|systems"
# hash_type: "platform" = per-platform hashes, "single" = hash = "...", "npm" = npmDepsHash, "both" = hash + npmDepsHash, "vendor" = hash + vendorHash
PACKAGES=(
  'termframe|binary-releases.nix|termframe = mkBinaryRelease|# Renovate:.*depName=.*termframe|platform|aarch64-darwin x86_64-darwin aarch64-linux x86_64-linux'
  'claude-code|binary-releases.nix|# Claude Code - agentic coding tool|# Renovate:.*depName=claude-code|platform|aarch64-darwin x86_64-darwin aarch64-linux x86_64-linux'
  'deck|standalone.nix|deck = _final: prev:|# Renovate:.*depName=.*deck|platform|aarch64-darwin x86_64-darwin aarch64-linux x86_64-linux'
  'octorus|binary-releases.nix|octorus = mkBinaryRelease|# Renovate:.*depName=.*octorus|platform|aarch64-darwin x86_64-darwin aarch64-linux x86_64-linux'
  'kakehashi|binary-releases.nix|kakehashi = mkBinaryRelease|# Renovate:.*depName=.*kakehashi|platform|aarch64-darwin x86_64-darwin aarch64-linux x86_64-linux'
  'playwright-cli|npm-packages.nix|playwright-cli = _final: prev: let|# Renovate:.*depName=@playwright/cli|npm|'
  'unocss-language-server|npm-packages.nix|unocss-language-server = _final: prev: let|# Renovate:.*depName=.*unocss-language-server|both|'
  'takt|npm-packages.nix|takt = _final: prev: let|# Renovate:.*depName=takt|both|'
  'cssmodules-language-server|source-builds.nix|cssmodules-language-server = _final: prev: {|# Renovate:.*depName=.*cssmodules-language-server|both|'
  'x-api-playground|source-builds.nix|x-api-playground = _final: prev: {|# Renovate:.*depName=.*playground|vendor|'
)

echo "=== Test: sed pattern matching for $OVERLAY_DIR ==="
echo ""

for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r name file sed_pattern renovate_pattern hash_type systems <<<"$entry"
  filepath="$OVERLAY_DIR/$file"

  echo "[$name] ($file)"

  # Test 1: セクション開始パターンのマッチ数 (sed -n でカウント、sed基本正規表現互換)
  match_count=$(sed -n "/$sed_pattern/p" "$filepath" 2>/dev/null | wc -l)
  if [ "$match_count" -eq 1 ]; then
    pass "section start pattern matches exactly once"
  elif [ "$match_count" -eq 0 ]; then
    fail "section start pattern NOT FOUND: /$sed_pattern/"
  else
    fail "section start pattern matches $match_count times (expected 1): /$sed_pattern/"
  fi

  # Test 2: sed 範囲内にセクション終了 (^  };) が到達可能か
  section=$(sed -n "/$sed_pattern/,/^  };/p" "$filepath" 2>/dev/null || echo "")
  if [ -n "$section" ]; then
    pass "section end (^  };) is reachable"
  else
    fail "section end (^  };) NOT reachable from start pattern"
  fi

  # Test 3: Renovate コメントからバージョン抽出
  version=$(grep -A 20 "$renovate_pattern" "$filepath" 2>/dev/null | sed -n 's/.*version = "\([^"]*\)".*/\1/p' | head -1 || echo "")
  if [ -n "$version" ]; then
    pass "version extracted: $version"
  else
    fail "version extraction failed for renovate pattern: /$renovate_pattern/"
  fi

  # Test 4: セクション内のハッシュパターン
  case "$hash_type" in
  platform)
    for sys in $systems; do
      if echo "$section" | grep -q "\"$sys\" = \"sha256-"; then
        pass "hash found for $sys"
      else
        fail "hash NOT found for $sys in section"
      fi
    done
    ;;
  single)
    if echo "$section" | grep -q 'hash = "sha256-'; then
      pass "hash pattern found"
    else
      fail "hash pattern NOT found in section"
    fi
    ;;
  npm)
    if echo "$section" | grep -q 'npmDepsHash = "sha256-'; then
      pass "npmDepsHash pattern found"
    else
      fail "npmDepsHash pattern NOT found in section"
    fi
    ;;
  both)
    if echo "$section" | grep -q 'hash = "sha256-\|npmDepsHash = "sha256-'; then
      pass "hash/npmDepsHash pattern found"
    else
      fail "hash/npmDepsHash pattern NOT found in section"
    fi
    ;;
  vendor)
    if echo "$section" | grep -q 'hash = "sha256-'; then
      pass "hash pattern found"
    else
      fail "hash pattern NOT found in section"
    fi
    if echo "$section" | grep -q 'vendorHash = "sha256-'; then
      pass "vendorHash pattern found"
    else
      fail "vendorHash pattern NOT found in section"
    fi
    ;;
  esac

  echo ""
done

# --- Test 5: ダミー値での sed 置換テスト ---
echo "=== Test: dry-run sed replacement ==="
echo ""

DUMMY_HASH="sha256-TESTDUMMYHASH000000000000000000000000000000="

# 各パッケージでダミーハッシュに置換し、反映されたか確認
DRY_RUN_PACKAGES=(
  'termframe|binary-releases.nix|termframe = mkBinaryRelease|aarch64-darwin'
  'deck|standalone.nix|deck = _final: prev:|aarch64-darwin'
  'octorus|binary-releases.nix|octorus = mkBinaryRelease|aarch64-darwin'
  'kakehashi|binary-releases.nix|kakehashi = mkBinaryRelease|aarch64-darwin'
)

# macOS (BSD sed) と Linux (GNU sed) の -i 互換ヘルパー
sedi() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

TMPFILE=$(mktemp)

for entry in "${DRY_RUN_PACKAGES[@]}"; do
  IFS='|' read -r name file sed_pattern target <<<"$entry"
  filepath="$OVERLAY_DIR/$file"

  cp "$filepath" "$TMPFILE"

  case "$target" in
  SINGLE)
    sedi "/$sed_pattern/,/^  };/{s|hash = \"sha256-[^\"]*\"|hash = \"${DUMMY_HASH}\"|;}" "$TMPFILE"
    ;;
  NPM)
    sedi "/$sed_pattern/,/^  };/{s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"${DUMMY_HASH}\"|;}" "$TMPFILE"
    ;;
  *)
    sedi "/$sed_pattern/,/^  };/{s|\"${target}\" = \"sha256-[^\"]*\"|\"${target}\" = \"${DUMMY_HASH}\"|;}" "$TMPFILE"
    ;;
  esac

  if grep -q "$DUMMY_HASH" "$TMPFILE"; then
    pass "$name: sed replacement applied successfully"
  else
    fail "$name: sed replacement had NO EFFECT"
  fi
done

# claude-code は特別なパターン（コメントでセクション検出）
cp "$OVERLAY_DIR/binary-releases.nix" "$TMPFILE"
sedi '/# Claude Code - agentic coding tool/,/^  };/{
  s|"aarch64-darwin" = "sha256-[^"]*"|"aarch64-darwin" = "'"${DUMMY_HASH}"'"|
}' "$TMPFILE"
if grep -q "$DUMMY_HASH" "$TMPFILE"; then
  pass "claude-code: sed replacement applied successfully"
else
  fail "claude-code: sed replacement had NO EFFECT"
fi

rm -f "$TMPFILE"

echo ""
echo "=== Results: $TESTS tests, $ERRORS failures ==="

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "ERROR: $ERRORS test(s) failed. The sed patterns in update-nix-hashes.yml"
  echo "       no longer match the overlay file structure."
  echo "       Fix the patterns or the overlay file before merging."
  exit 1
fi

echo "All tests passed."
