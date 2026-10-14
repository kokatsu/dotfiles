#!/usr/bin/env bash
set -euo pipefail

profile=$1
target=$2
directory=$(dirname "$target")
mkdir -p "$directory"
temporary=$(mktemp "$directory/.karabiner.json.XXXXXX")
trap 'rm -f "$temporary"' EXIT

if [[ -f "$target" ]]; then
  cp -p "$target" "$temporary"
  source=$target
else
  source="$temporary.initial"
  trap 'rm -f "$temporary" "$source"' EXIT
  printf '%s\n' '{"global":{},"profiles":[{"name":"Default","selected":true}]}' >"$source"
fi

jq --slurpfile managed "$profile" '
  (.profiles | map(.name) | index("Default")) as $index
  | if $index == null then error("Karabiner Default profile not found")
    else .profiles[$index] += $managed[0] end
' "$source" >"$temporary"
mv "$temporary" "$target"
