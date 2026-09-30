#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE" ]] && exit 0

# readlink -f resolves symlinks in every path component, so files under a
# symlinked directory (e.g. ~/.config/claude/skills -> /nix/store/...) are
# caught, not just directly symlinked files. mkOutOfStoreSymlink targets
# canonicalize to the repository, not the store, so they still pass.
# macOS readlink -f fails when the last component does not exist, so a new
# file is resolved through its parent instead.
if [[ -e $FILE || -L $FILE ]]; then
  CANON=$(readlink -f -- "$FILE" 2>/dev/null || true)
else
  PARENT=$(cd -P -- "$(dirname -- "$FILE")" 2>/dev/null && pwd -P) || PARENT=""
  CANON=${PARENT:+$PARENT/$(basename -- "$FILE")}
fi
if [[ "$CANON" == /nix/store/* ]]; then
  echo "Do not edit Home Manager managed paths directly. Edit the corresponding source in the repository's nix/home/ or .config/ directory instead." >&2
  exit 2
fi
