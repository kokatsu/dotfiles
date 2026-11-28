#!/usr/bin/env bash
set -eEuo pipefail
# shellcheck source=scripts/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"
trap 'report_failure "$LINENO"' ERR

repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# Run the evaluated merge function in the fixture, without invoking the other activation steps.
# homeConfigurations read USER and DOTFILES_DIR from the environment, so the eval must be impure.
env -u SUDO_USER USER=activation-test DOTFILES_DIR="$repo_root" \
  nix eval --impure --raw "$repo_root#homeConfigurations.activation-test.config.home.activation.mergeCodexConfig.data" \
  >"$test_dir/activation.sh"
if ! awk '/^mergeCodexConfig\(\) \{$/ { body = 1 } body { print } body && /^}$/ { body = 0; done = 1 } END { exit !done }' \
  "$test_dir/activation.sh" >"$test_dir/merge.sh"; then
  echo 'Could not extract mergeCodexConfig from the Home Manager activation script' >&2
  exit 1
fi

# The activation must merge both the host and the nono-agent Codex configs.
calls=$(
  # shellcheck disable=SC2329 # called by the sourced activation lines
  mergeCodexConfig() { printf '%s %s\n' "$1" "$2"; }
  # shellcheck source=/dev/null
  source <(grep '^mergeCodexConfig ' "$test_dir/activation.sh")
)
[[ $(wc -l <<<"$calls") -eq 2 ]]
grep -Eq '^/[^ ]*/\.config/codex /nix/store/[^ ]+-codex-config\.toml$' <<<"$calls"
grep -Eq '^/[^ ]*/\.local/share/nono-agent/codex /nix/store/[^ ]+-codex-config\.toml$' <<<"$calls"

# shellcheck source=/dev/null
source "$test_dir/merge.sh"

export DRY_RUN_CMD=''
codex_dir="$test_dir/codex"
base="$test_dir/base.toml"
target="$codex_dir/config.toml"
printf 'model = "managed-model"\n[sandbox_workspace_write]\nwritable_roots = ["/home/test/.local/share/Trash"]\n[tui]\nnotifications = true\n' >"$base"
chmod 444 "$base"

# A fresh installation must be writable even though the store source is not.
mergeCodexConfig "$codex_dir" "$base"
cmp "$base" "$target"
[[ -w "$target" ]]
[[ $(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target") == 600 ]]

cat >"$target" <<'TOML'
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
cp "$target" "$test_dir/before.toml"
DRY_RUN_CMD='echo' mergeCodexConfig "$codex_dir" "$base" >/dev/null
cmp "$target" "$test_dir/before.toml"

mergeCodexConfig "$codex_dir" "$base"
grep -Fq 'model = "managed-model"' "$target"
grep -Fq 'notifications = true' "$target"
grep -Fq 'writable_roots = ["/home/test/.local/share/Trash"]' "$target"
grep -Fq '[notice]' "$target"
grep -Fq 'hide_tip = true' "$target"
grep -Fq '[projects."/tmp/project with spaces"]' "$target"
grep -Fq 'trust_level = "trusted"' "$target"
grep -Fq '[tui.model_availability_nux]' "$target"
grep -Fq '"test-model" = 1' "$target"
grep -Fq '[hooks.state."session-start"]' "$target"
grep -Fq 'trusted = true' "$target"
if grep -Eq 'old-model|obsolete|notifications = false' "$target"; then
  echo 'Unmanaged base settings survived activation' >&2
  exit 1
fi

# Repeated activations must not duplicate local tables.
cp "$target" "$test_dir/once.toml"
mergeCodexConfig "$codex_dir" "$base"
cmp "$target" "$test_dir/once.toml"
[[ -w "$target" ]]
[[ $(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target") == 600 ]]
if compgen -G "$test_dir/.codex-*" >/dev/null; then
  echo 'Activation left temporary files in the parent directory' >&2
  exit 1
fi

# A symlinked config.toml is replaced, and the file it points to is left alone.
printf '[notice]\nhide_tip = true\n' >"$test_dir/outside.toml"
cp "$test_dir/outside.toml" "$test_dir/outside.orig"
link_dir="$test_dir/codex-link"
mkdir -p "$link_dir"
ln -s "$test_dir/outside.toml" "$link_dir/config.toml"
mergeCodexConfig "$link_dir" "$base"
[[ ! -L "$link_dir/config.toml" && -f "$link_dir/config.toml" ]]
cmp "$base" "$link_dir/config.toml"
cmp "$test_dir/outside.toml" "$test_dir/outside.orig"

# A symlinked rules directory is refused without touching its target.
rules_dir="$test_dir/codex-rules"
mkdir -p "$rules_dir" "$test_dir/outside-rules"
printf 'outside\n' >"$test_dir/outside-rules/managed.rules"
ln -s "$test_dir/outside-rules" "$rules_dir/rules"
# A separate bash -e keeps errexit on inside the function, so only the rules guard can explain the refusal.
if bash -eu -c 'source "$1"; mergeCodexConfig "$2" "$3"' _ "$test_dir/merge.sh" "$rules_dir" "$base" \
  2>"$test_dir/refusal.err"; then
  echo 'Activation accepted a symlinked rules directory' >&2
  exit 1
fi
grep -Fq "$rules_dir/rules is not a real directory" "$test_dir/refusal.err"
cmp "$base" "$rules_dir/config.toml"
[[ $(<"$test_dir/outside-rules/managed.rules") == outside ]]
if compgen -G "$test_dir/.codex-*" >/dev/null; then
  echo 'Refused activation left temporary files in the parent directory' >&2
  exit 1
fi
printf 'Codex configuration activation tests passed\n'
