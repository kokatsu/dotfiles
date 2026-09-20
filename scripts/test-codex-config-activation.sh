#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# Exercise the actual activation branch with a read-only generated base.
# shellcheck disable=SC2016
awk '/        if \[ -f "\$TARGET" \]; then/ {active=1} /        RULES_DIR=/ {active=0} active' \
  "$repo_root/nix/home/programs/codex.nix" |
  sed -e 's|${pkgs.gawk}/bin/awk|awk|g' \
    -e 's|${pkgs.coreutils}/bin/install|install|g' >"$test_dir/activate.sh"
[[ -s "$test_dir/activate.sh" ]]

export BASE="$test_dir/base.toml" TARGET="$test_dir/config.toml" DRY_RUN_CMD=''
printf 'model = "managed-model"\n[tui]\nnotifications = true\n' >"$BASE"
chmod 444 "$BASE"

# A fresh installation must be writable even though the store source is not.
bash -eu "$test_dir/activate.sh"
cmp "$BASE" "$TARGET"
[[ -w "$TARGET" ]]
[[ $(stat -c '%a' "$TARGET" 2>/dev/null || stat -f '%Lp' "$TARGET") == 600 ]]

cat >"$TARGET" <<'TOML'
model = "old-model"
[notice]
hide_tip = true
[features]
obsolete = true
[projects."/tmp/project with spaces"]
trust_level = "trusted"
[tui]
notifications = false
[tui.model_availability_nux]
"test-model" = 1
[hooks.state."session-start"]
trusted = true
TOML

# Dry runs preserve both content and mode.
cp "$TARGET" "$test_dir/before.toml"
DRY_RUN_CMD='echo' bash -eu "$test_dir/activate.sh" >/dev/null
cmp "$TARGET" "$test_dir/before.toml"

bash -eu "$test_dir/activate.sh"
grep -Fq 'model = "managed-model"' "$TARGET"
grep -Fq 'notifications = true' "$TARGET"
grep -Fq '[notice]' "$TARGET"
grep -Fq 'hide_tip = true' "$TARGET"
grep -Fq '[projects."/tmp/project with spaces"]' "$TARGET"
grep -Fq 'trust_level = "trusted"' "$TARGET"
grep -Fq '[tui.model_availability_nux]' "$TARGET"
grep -Fq '"test-model" = 1' "$TARGET"
grep -Fq '[hooks.state."session-start"]' "$TARGET"
grep -Fq 'trusted = true' "$TARGET"
if grep -Eq 'old-model|obsolete|notifications = false' "$TARGET"; then
  echo 'Unmanaged base settings survived activation' >&2
  exit 1
fi

# Repeated activations must not duplicate local tables.
cp "$TARGET" "$test_dir/once.toml"
bash -eu "$test_dir/activate.sh"
cmp "$TARGET" "$test_dir/once.toml"
[[ -w "$TARGET" ]]
printf 'Codex configuration activation tests passed\n'
