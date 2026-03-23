#!/usr/bin/env bash
# Test coverage using readelf + GDB breakpoints.
# Extracts address→file:line from DWARF, sets breakpoints, runs tests,
# and reports which source lines were executed.
#
# Usage: coverage.sh <source-dir> <binary1> [binary2 ...]
set -euo pipefail

SRC_DIR="${1:?Usage: coverage.sh <source-dir> <binary1> [binary2 ...]}"
shift
BINS=("$@")
if [ ${#BINS[@]} -eq 0 ]; then
  echo "Error: at least one binary required" >&2
  exit 1
fi
SRC_DIR_ABS="$(cd "$SRC_DIR" && pwd)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# awk snippet for extracting addr→file:line (shared across binaries)
# shellcheck disable=SC2016
EXTRACT_AWK='
  /^\/.*:$/ {
    path = $0; sub(/:$/, "", path)
    in_src = (index(path, srcdir) == 1)
    if (in_src) { n = split(path, parts, "/"); current_file = parts[n] }
    next
  }
  in_src && /^[a-zA-Z_].*\.zig / {
    file = $1; line = $2; addr = $3
    if (addr == "" || addr == "0x0") next
    gsub(/^0x0+/, "0x", addr)
    if (addr == "0x") next
    if (file == current_file) print addr "\t" file "\t" line
  }
'

# 1. Extract address→file:line from each binary (normalized, per-binary + merged)
: >"$TMPDIR/addr_map.tsv"
for i in "${!BINS[@]}"; do
  readelf --debug-dump=decodedline "${BINS[$i]}" 2>/dev/null |
    awk -v srcdir="$SRC_DIR_ABS" "$EXTRACT_AWK" |
    sort -u >"$TMPDIR/addr_map_${i}.tsv"
  cat "$TMPDIR/addr_map_${i}.tsv" >>"$TMPDIR/addr_map.tsv"
done
sort -u -o "$TMPDIR/addr_map.tsv" "$TMPDIR/addr_map.tsv"

TOTAL_ADDRS=$(awk '{print $1}' "$TMPDIR/addr_map.tsv" | sort -u | wc -l)
echo "Found $TOTAL_ADDRS executable addresses in source files"

if [ "$TOTAL_ADDRS" -eq 0 ]; then
  echo "Error: no addresses found. Is the binary patched?" >&2
  exit 1
fi

# 2. Find GDB
GDB=$(command -v gdb 2>/dev/null || echo "")
if [ -z "$GDB" ]; then
  echo "Error: gdb not found. Install gdb or run: nix shell nixpkgs#gdb" >&2
  exit 1
fi

# 3. Run GDB on each binary
: >"$TMPDIR/hit_addrs.txt"

for i in "${!BINS[@]}"; do
  BIN="${BINS[$i]}"
  MAP="$TMPDIR/addr_map_${i}.tsv"
  ADDR_FILE="$TMPDIR/addrs_${i}.txt"

  awk '{print $1}' "$MAP" | sort -u >"$ADDR_FILE"
  ADDR_COUNT=$(wc -l <"$ADDR_FILE")

  if [ "$ADDR_COUNT" -eq 0 ]; then continue; fi

  {
    echo "set pagination off"
    echo "set confirm off"
    awk '{print "break *" $1}' "$ADDR_FILE"
    seq 1 "$ADDR_COUNT" | while read -r j; do
      echo "commands $j"
      echo "  silent"
      echo "  continue"
      echo "end"
    done
    echo "run"
    echo "info breakpoints"
    echo "quit"
  } >"$TMPDIR/gdb_script_${i}.gdb"

  echo "Running $(basename "$BIN") under GDB with $ADDR_COUNT breakpoints..."
  "$GDB" -batch -x "$TMPDIR/gdb_script_${i}.gdb" "$BIN" >"$TMPDIR/gdb_output_${i}.log" 2>&1

  grep -B1 "breakpoint already hit" "$TMPDIR/gdb_output_${i}.log" |
    grep -oP '0x[0-9a-f]+' |
    sed 's/0x0*/0x/' |
    sort -u >>"$TMPDIR/hit_addrs.txt"
done

sort -u -o "$TMPDIR/hit_addrs.txt" "$TMPDIR/hit_addrs.txt"

HIT_COUNT=$(wc -l <"$TMPDIR/hit_addrs.txt")
echo "Hit $HIT_COUNT / $TOTAL_ADDRS addresses"
echo ""

# 4. Cross-reference: a line is covered if ANY of its addresses was hit
awk -v hitfile="$TMPDIR/hit_addrs.txt" '
BEGIN {
  while ((getline addr < hitfile) > 0) hit[addr] = 1
}
{
  addr = $1; file = $2; line = $3
  key = file SUBSEP line
  if (!(key in line_file)) {
    line_file[key] = file
    files[file] = 1
  }
  if (addr in hit) covered[key] = 1
}
END {
  for (key in line_file) {
    file = line_file[key]
    total_lines[file]++
    total_all++
    if (key in covered) {
      covered_lines[file]++
      covered_all++
    }
  }
  printf "\n%-20s %8s %8s %8s\n", "File", "Covered", "Total", "Coverage"
  printf "%-20s %8s %8s %8s\n", "----", "-------", "-----", "--------"
  n = asorti(files, sorted_files)
  for (i = 1; i <= n; i++) {
    f = sorted_files[i]
    cov = covered_lines[f] + 0
    tot = total_lines[f] + 0
    if (tot > 0) pct = cov / tot * 100; else pct = 0
    printf "%-20s %8d %8d %7.1f%%\n", f, cov, tot, pct
  }
  if (total_all > 0) pct = covered_all / total_all * 100; else pct = 0
  printf "%-20s %8s %8s %8s\n", "----", "-------", "-----", "--------"
  printf "%-20s %8d %8d %7.1f%%\n", "TOTAL", covered_all+0, total_all+0, pct
}
' "$TMPDIR/addr_map.tsv"
