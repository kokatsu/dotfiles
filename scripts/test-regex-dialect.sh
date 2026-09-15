#!/usr/bin/env bash
# test-regex-dialect.sh — check-regex-dialect.sh が変換器の故障で落ちることを検証する。
#
# [:space:] の置換先が壊れると pipe-to-shell と base64-to-shell が全件 allow に
# 転ぶ。壊した helper を食わせて、checker が非ゼロで落ちることを固定する。
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
checker="$repo_root/scripts/check-regex-dialect.sh"
helper="$repo_root/scripts/regex-dialect-check.ts"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

TESTS=0
ERRORS=0

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

# $1: 期待する終了コードの種類 (zero|nonzero), $2: ラベル, $3: helper のパス,
# $4: BMP 走査を飛ばすか (skip-scan のとき飛ばす)
expect_exit() {
  local want=$1 label=$2 use_helper=$3 skip=${4:-}
  local rc=0
  REGEX_DIALECT_HELPER="$use_helper" \
    REGEX_DIALECT_SKIP_SCAN="$([[ $skip == skip-scan ]] && echo 1 || echo 0)" \
    bash "$checker" >/dev/null 2>&1 || rc=$?
  case $want in
  zero)
    if [[ $rc -eq 0 ]]; then
      pass "$label (exit 0)"
    else
      fail "$label: expected exit 0, got $rc"
    fi
    ;;
  nonzero)
    if [[ $rc -ne 0 ]]; then
      pass "$label (exit $rc)"
    else
      fail "$label: expected nonzero, got 0"
    fi
    ;;
  esac
}

# 元の helper をコピーし、sed 式 $1 で壊した複製のパスを返す
broken_helper() {
  local expression=$1 name=$2
  local path="$work/$name.ts"
  cp "$helper" "$path"
  sedi "$expression" "$path"
  if diff -q "$helper" "$path" >/dev/null; then
    echo "mutation did not apply: $name" >&2
    exit 1
  fi
  echo "$path"
}

echo "=== Test: check-regex-dialect.sh (変換器の故障検出) ==="
echo ""

# ここだけ BMP 走査を含めて全経路を通す
expect_exit zero "無改変の helper" "$helper"

# 以降は変換器を壊して落ちることだけを見るので走査を飛ばす

# [:space:] を literal X にすると、パイプと shell 名の間の空白が一致しなくなり
# pipe-to-shell と base64-to-shell が両方 allow へ転ぶ
expect_exit nonzero "[:space:] の置換先が壊れている" \
  "$(broken_helper 's|"\\\\s"|"X"|' space-literal)" skip-scan

# [:alnum:] の置換先を壊すと [^BROKEN_] になり、末尾の境界判定が変わる
expect_exit nonzero "[:alnum:] の置換先が壊れている" \
  "$(broken_helper 's|"A-Za-z0-9"|"BROKEN"|' alnum-broken)" skip-scan

# 置換自体を行わなければ POSIX クラスが RegExp へそのまま渡り、別物になる
expect_exit nonzero "置換が行われない" \
  "$(broken_helper 's|\.replaceAll("\[:space:\]", "\\\\s")||' no-space-replace)" skip-scan

echo ""
echo "=== Results: $TESTS tests, $ERRORS failures ==="

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "ERROR: $ERRORS test(s) failed."
  exit 1
fi

echo "All tests passed."
