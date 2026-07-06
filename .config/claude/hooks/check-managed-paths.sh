#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE" ]] && exit 0

# readlink -f resolves symlinks in every path component, so files under a
# symlinked directory (e.g. ~/.config/claude/skills -> /nix/store/...) are
# caught, not just directly symlinked files. mkOutOfStoreSymlink targets
# canonicalize to the repository, not the store, so they still pass.
CANON=$(readlink -f -- "$FILE" 2>/dev/null || true)
if [[ "$CANON" == /nix/store/* ]]; then
  echo "Do not edit Home Manager managed paths directly. Edit the corresponding file in the repository's .config/ directory instead." >&2
  exit 2
fi
