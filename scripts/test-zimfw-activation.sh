#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/zim"
# Run the actual activation branch with only external commands substituted.
# shellcheck disable=SC2016
awk '/        LAST_ZIMRC=/ {active=1} /        # zeno / {active=0} active' \
  "$repo_root/nix/home/programs/zsh.nix" |
  sed 's|${pkgs.zsh}/bin/zsh|fake-zsh|g' >"$test_dir/activation.sh"
cat >"$test_dir/bin/fake-zsh" <<'MOCK'
#!/usr/bin/env bash
printf 'called\n' >>"$ZIM_HOME/calls"
exit "$FAKE_ZIM_RESULT"
MOCK
cat >"$test_dir/bin/pkill" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH"
export ZIM_HOME="$test_dir/zim" ZIM_CONFIG_FILE="$test_dir/zimrc" DRY_RUN_CMD=''
printf 'old\n' >"$ZIM_HOME/.last_zimrc"
printf 'new\n' >"$ZIM_CONFIG_FILE"
touch "$ZIM_HOME/init.zsh"
FAKE_ZIM_RESULT=23 bash -eu "$test_dir/activation.sh"
[[ $(cat "$ZIM_HOME/.last_zimrc") == old ]]
FAKE_ZIM_RESULT=0 bash -eu "$test_dir/activation.sh"
cmp "$ZIM_CONFIG_FILE" "$ZIM_HOME/.last_zimrc"
FAKE_ZIM_RESULT=23 bash -eu "$test_dir/activation.sh"
[[ $(wc -l <"$ZIM_HOME/calls") -eq 2 ]]
printf 'changed\n' >"$ZIM_CONFIG_FILE"
DRY_RUN_CMD=echo FAKE_ZIM_RESULT=0 bash -eu "$test_dir/activation.sh"
[[ $(cat "$ZIM_HOME/.last_zimrc") == new ]]
[[ $(wc -l <"$ZIM_HOME/calls") -eq 2 ]]
printf 'Zim activation retry tests passed\n'
