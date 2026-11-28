#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
hook="$repo_root/.codex/hooks/format-post-tool-use.sh"
cd "$workdir"
printf '{"probe":[1,2]}\n' >"$workdir/probe.json"
jq -nc --arg path "$workdir/probe.json" \
  '{tool_name:"Write", tool_input:{file_path:$path}}' | bash "$hook"
biome format --stdin-file-path=probe.json <"$workdir/probe.json" >"$workdir/expected"
cmp "$workdir/probe.json" "$workdir/expected"

printf '{"probe":[1,2]}\n' >"moved file.json"
jq -nc --arg command '*** Update File: old.json
*** Move to: moved file.json' \
  '{tool_name:"apply_patch", tool_input:{command:$command}}' | bash "$hook"
biome format --stdin-file-path='moved file.json' <'moved file.json' >"$workdir/expected"
cmp 'moved file.json' "$workdir/expected"
printf 'const value=<div>ok</div>;\n' >probe.tsx
jq -nc '{tool_name:"Write", tool_input:{file_path:"probe.tsx"}}' | bash "$hook"
deno fmt --check probe.tsx

git init -q
cp "$repo_root/.gitignore" .gitignore
cp "$repo_root/.biome.jsonc" .biome.jsonc
mkdir -p .config/claude
printf '{"probe":[1,2]}\n' >.config/claude/settings.json
cp .config/claude/settings.json ignored-original
output=$(jq -nc '{tool_name:"Write", tool_input:{file_path:".config/claude/settings.json"}}' | bash "$hook")
[[ -z $output ]]
cmp ignored-original .config/claude/settings.json

mkdir "$workdir/bin"
printf '#!/usr/bin/env bash\necho formatter-failed >&2\nexit 23\n' >"$workdir/bin/biome"
chmod +x "$workdir/bin/biome"
output=$(jq -nc --arg path "$workdir/probe.json" \
  '{tool_name:"Write", tool_input:{file_path:$path}}' | PATH="$workdir/bin:$PATH" bash "$hook")
printf '%s' "$output" | jq -e '.systemMessage | contains("formatter-failed")' >/dev/null
printf 'format hook: actual formatter and failure diagnostic passed\n'
