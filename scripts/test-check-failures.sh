#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cat >"$test_dir/selene" <<'MOCK'
#!/usr/bin/env bash
[[ $PWD != */nvim ]] || exit 23
MOCK
cat >"$test_dir/deno" <<'MOCK'
#!/usr/bin/env bash
if [[ $PWD == */karabiner-config || "$*" == *karabiner-config* || "$*" == *zeno/config.ts* ]]; then
  exit 23
fi
MOCK
chmod +x "$test_dir/selene" "$test_dir/deno"
cd "$repo_root"
export PATH="$test_dir:$PATH"
for recipe in lua-lint deno-lint deno-fmt-check deno-check; do
  if just "$recipe" >"$test_dir/output" 2>&1; then
    echo "Expected failure from $recipe" >&2
    exit 1
  fi
done
# Exercise the second loop (explicit files) after all directory checks pass.
if just --set deno_dirs scripts deno-check >"$test_dir/output" 2>&1; then exit 1; fi
if just --set deno_dirs scripts deno-lint >"$test_dir/output" 2>&1; then exit 1; fi
printf 'Check failure propagation tests passed\n'
