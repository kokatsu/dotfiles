# shellcheck shell=bash
# Helpers shared by the scripts/test-*.sh suites. Source it; do not run it.
# BASH_SOURCE[1] is the test that called the helper, so failures name that file.

# Use as: trap 'report_failure "$LINENO"' ERR
report_failure() {
  local rc=$? line=$1
  printf '%s:%s: exit %s: %s\n' "${BASH_SOURCE[1]##*/}" "$line" "$rc" "$BASH_COMMAND" >&2
}

unexpected_success() {
  printf '%s:%s: expected a failure, but the command succeeded\n' "${BASH_SOURCE[1]##*/}" "$1" >&2
  exit 1
}

# The caller initializes failures=0 and exits non-zero when it is positive.
pass() { echo "  PASS $1"; }
fail() {
  echo "  FAIL $1" >&2
  failures=$((failures + 1))
}
