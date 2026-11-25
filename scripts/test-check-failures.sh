#!/usr/bin/env bash
set -eEuo pipefail
# shellcheck source=scripts/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"
trap 'report_failure "$LINENO"' ERR
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cat >"$test_dir/selene" <<'MOCK'
#!/usr/bin/env bash
[[ $PWD != */nvim ]] || exit 23
MOCK
cat >"$test_dir/deno" <<'MOCK'
#!/usr/bin/env bash
if [[ "$PWD $*" == *"$DENO_FAIL_TARGET"* ]]; then
  exit 23
fi
MOCK
cat >"$test_dir/typos" <<'MOCK'
#!/usr/bin/env bash
exit 23
MOCK
cat >"$test_dir/gofmt" <<'MOCK'
#!/usr/bin/env bash
case "$GOFMT_TEST_MODE" in
error) echo 'gofmt failed' >&2; exit 23 ;;
diff) echo 'tools/example.go' ;;
clean) exit 0 ;;
esac
MOCK
chmod +x "$test_dir/selene" "$test_dir/deno" "$test_dir/typos" "$test_dir/gofmt"
cd "$repo_root"
export PATH="$test_dir:$PATH"
for mode in error diff; do
  if GOFMT_TEST_MODE=$mode just go-fmt-check >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
done
GOFMT_TEST_MODE=clean just go-fmt-check
export DENO_FAIL_TARGET=karabiner-config
for recipe in lua-lint deno-lint deno-fmt-check deno-check; do
  if just "$recipe" >"$test_dir/output" 2>&1; then
    echo "Expected failure from $recipe" >&2
    exit 1
  fi
done
# Only an explicit file can trigger this failure.
export DENO_FAIL_TARGET=zeno/config.ts
if just deno-check >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
if just deno-fmt-check >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
if just deno-lint >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
# A failed recipe must not stop the ones after it, and only it is reported.
if just _run-all "typos nvim-test" >"$test_dir/output" 2>&1; then unexpected_success "$LINENO"; fi
grep -Fqx 'failed: typos' "$test_dir/output"
grep -Fq '=== Results:' "$test_dir/output"
printf 'Check failure propagation tests passed\n'
