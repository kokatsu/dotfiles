#!/usr/bin/env bash
set -euo pipefail

profile=$1
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
apply=$2
target=$workdir/karabiner.json

bash "$apply" "$profile" "$target"
jq -e '.profiles[0].name == "Default" and .profiles[0].selected == true' "$target" >/dev/null

cat >"$target" <<'EOF'
{"global":{"show_in_menu_bar":false},"profiles":[{"name":"Other","selected":true,"devices":[{"ignored":true}]},{"name":"Default","selected":false,"devices":[{"ignored":false}],"complex_modifications":{"rules":[]},"simple_modifications":[]}]}
EOF
bash "$apply" "$profile" "$target"
jq -e --slurpfile managed "$profile" '
  .global.show_in_menu_bar == false
  and .profiles[0] == {"name":"Other","selected":true,"devices":[{"ignored":true}]}
  and .profiles[1].selected == false
  and .profiles[1].devices == [{"ignored":false}]
  and .profiles[1].complex_modifications == $managed[0].complex_modifications
  and .profiles[1].simple_modifications == $managed[0].simple_modifications
' "$target" >/dev/null
cp "$target" "$workdir/first.json"
bash "$apply" "$profile" "$target"
cmp "$target" "$workdir/first.json"

echo '{"profiles":[{"name":"Other","selected":true}]}' >"$target"
cp "$target" "$workdir/invalid.json"
if bash "$apply" "$profile" "$target" 2>/dev/null; then
  echo 'Expected missing Default profile to fail' >&2
  exit 1
fi
cmp "$target" "$workdir/invalid.json"
echo 'Karabiner profile: initial setup, preserved settings, idempotence and failure passed'
