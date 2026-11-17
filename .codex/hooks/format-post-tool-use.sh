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
    -e 's/^\*\*\* Update File: //p' \
    -e 's/^\*\*\* Move to: //p'
)

format_file() {
  local file="$1"
  [ -f "$file" ] || return 0

  case "$file" in
  *.nix)
    alejandra -q "$file"
    ;;
  *.lua)
    stylua "$file"
    ;;
  *.ts | *.tsx)
    # このリポジトリの .ts は全て Deno 管理 (.biome.jsonc で除外) のため deno fmt を使う
    deno fmt "$file"
    ;;
  *.js | *.json | *.jsonc)
    biome check --write --no-errors-on-unmatched "$file"
    ;;
  *.yaml | *.yml)
    yamlfmt "$file"
    ;;
  esac
}

failures=''
while IFS= read -r file; do
  if ! output=$(format_file "$file" 2>&1); then
    failures+="$file: $output
"
  fi
done < <({
  printf '%s\n' "$json_paths"
  printf '%s\n' "$patch_paths"
} | sed '/^$/d' | sort -u)

if [[ -n $failures ]]; then
  jq -n --arg message "Auto-format failed:
$failures" '{systemMessage: $message}'
fi

exit 0
