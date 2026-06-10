#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

json_paths=$(
  printf '%s' "$input" | jq -r '
    if (.tool_input | type) == "object" then
      [
        .tool_input.file_path?,
        .tool_input.path?,
        .tool_input.file?,
        .tool_input.files[]?,
        .tool_input.edits[]?.file_path?,
        .tool_input.edits[]?.path?
      ]
      | map(select(type == "string" and length > 0))
      | .[]
    else
      empty
    end
  ' 2>/dev/null || true
)

command=$(
  printf '%s' "$input" | jq -r '
    if (.tool_input | type) == "string" then
      .tool_input
    elif (.tool_input | type) == "object" then
      .tool_input.command? // .tool_input.patch? // .tool_input.input? // empty
    else
      empty
    end
  ' 2>/dev/null || true
)

patch_paths=$(
  printf '%s\n' "$command" | sed -n \
    -e 's/^\*\*\* Add File: //p' \
    -e 's/^\*\*\* Update File: //p'
)

format_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  case "$file" in
  *.nix)
    alejandra -q "$file" 2>/dev/null || true
    ;;
  *.lua)
    stylua "$file" 2>/dev/null || true
    ;;
  *.js | *.ts | *.json | *.jsonc)
    biome check --write "$file" >/dev/null 2>&1 || true
    ;;
  *.yaml | *.yml)
    yamlfmt "$file" 2>/dev/null || true
    ;;
  esac
}

{
  printf '%s\n' "$json_paths"
  printf '%s\n' "$patch_paths"
} | sed '/^$/d' | sort -u | while IFS= read -r file; do
  format_file "$file"
done

exit 0
