#!/usr/bin/env bash
# Generate test coverage using readelf + GDB breakpoints.
# Works around Zig 0.15 DWARF v5 incompatibility with kcov/callgrind.
#
# Usage: ./scripts/cover.sh
#   or:  zig build cover
set -euo pipefail

cd "$(dirname "$0")/.."

BIN=zig-out/test-bin
PATCHED=zig-out/test-bin-patched

mkdir -p zig-out

echo "=== Step 1: Build test binary ==="
zig test --test-no-exec -femit-bin="$BIN" src/main.zig 2>&1

echo "=== Step 2: Patch DWARF (strip DW_LNCT_LLVM_source) ==="
STRIP_DWARF=zig-out/bin/strip-dwarf
if [ ! -x "$STRIP_DWARF" ]; then
  zig build -Doptimize=ReleaseFast 2>&1 | grep -v "^$"
fi
"$STRIP_DWARF" "$BIN" "$PATCHED"
chmod +x "$PATCHED"

echo ""
echo "=== Step 3: Run coverage ==="
bash scripts/coverage.sh src "$PATCHED"
