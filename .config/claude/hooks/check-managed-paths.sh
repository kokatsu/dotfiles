#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE" ]] && exit 0

if [[ -L "$FILE" ]] && [[ "$(readlink "$FILE")" == /nix/store/* ]]; then
  echo "Do not edit Home Manager managed paths directly. Edit the corresponding file in the repository's .config/ directory instead." >&2
  exit 2
fi
