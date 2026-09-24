#!/usr/bin/env bash
set -eEuo pipefail
report_failure() {
  local rc=$? line=$1
  printf '%s:%s: exit %s: %s\n' "${BASH_SOURCE[0]##*/}" "$line" "$rc" "$BASH_COMMAND" >&2
}
trap 'report_failure "$LINENO"' ERR
unexpected_success() {
  printf '%s:%s: expected a failure, but the command succeeded\n' "${BASH_SOURCE[0]##*/}" "$1" >&2
  exit 1
}
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
cat >"$test_dir/typos" <<'MOCK'
#!/usr/bin/env bash
exit 23
MOCK
chmod +x "$test_dir/selene" "$test_dir/deno" "$test_dir/typos"
cd "$repo_root"
export PATH="$test_dir:$PATH"
for recipe in lua-lint deno-lint deno-fmt-check deno-check; do
  if just "$recipe" >"$test_dir/output" 2>&1; then
    echo "Expected failure from $recipe" >&2
    exit 1
  fi
done
# Exercise the second loop (explicit files) after all directory checks pass.
if just --set deno_dirs scripts deno-check >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
if just --set deno_dirs scripts deno-lint >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
# A failed recipe must not stop the ones after it, and only it is reported.
if just _run-all "typos nvim-test" >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
grep -Fqx 'failed: typos' "$test_dir/output"
grep -Fq '=== Results:' "$test_dir/output"
printf 'Check failure propagation tests passed\n'
