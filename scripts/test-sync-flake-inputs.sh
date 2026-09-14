#!/usr/bin/env bash
# sync-flake-inputs.sh の終了コードと出力を、偽の origin と偽の deno / nix で確認する
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

# origin/main に旧 flake.nix、作業ツリーに新 flake.nix を用意する
git init -q "$test_dir/origin"
git -C "$test_dir/origin" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
git -C "$test_dir/origin" branch -M main
printf 'old\n' >"$test_dir/origin/flake.nix"
git -C "$test_dir/origin" add flake.nix
git -C "$test_dir/origin" -c user.name=t -c user.email=t@example.com commit -q -m flake
git clone -q "$test_dir/origin" "$test_dir/work"
printf 'new\n' >"$test_dir/work/flake.nix"

cat >"$test_dir/bin/nix" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SYNC_TEST_DIR/nix-calls"
MOCK
cat >"$test_dir/bin/deno" <<'MOCK'
#!/usr/bin/env bash
if [[ -e "$SYNC_TEST_DIR/deno-fail" ]]; then exit 23; fi
input=$(cat)
if [[ $input == new ]]; then
  printf 'hermes-agent github:NousResearch/hermes-agent/v2.0.0\n'
else
  printf 'hermes-agent github:NousResearch/hermes-agent/v1.0.0\n'
fi
MOCK
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH" SYNC_TEST_DIR="$test_dir"
cd "$test_dir/work"

# 解析の失敗は同期スクリプトの失敗として伝わらなければならない
touch "$test_dir/deno-fail"
if bash "$repo_root/scripts/sync-flake-inputs.sh" "$test_dir/out-fail" 2>/dev/null; then
  echo "sync must fail when the flake parser fails" >&2
  exit 1
fi
[[ ! -e "$test_dir/nix-calls" ]]
rm "$test_dir/deno-fail"

# 変わった input だけを nix flake update に渡し、名前とタグを出力する
bash "$repo_root/scripts/sync-flake-inputs.sh" "$test_dir/out-ok"
grep -Fxq 'extra_packages=hermes-agent v2.0.0' "$test_dir/out-ok"
grep -Fxq 'flake update hermes-agent' "$test_dir/nix-calls"
printf 'sync-flake-inputs tests passed\n'
