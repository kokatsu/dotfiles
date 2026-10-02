#!/usr/bin/env bash
# Launcher for transcript-grep-guard.ts.
#
# It exists so settings.json names one command per hook and so the Deno
# permission set can be built from paths this script resolves.
#
# Every failure here prints nothing and exits 0: the command then goes through
# the normal permission check, so this hook can only remove a prompt, never add
# one.
set -uo pipefail

[[ -t 0 ]] && exit 0

HOOKS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 0
script="$HOOKS_DIR/transcript-grep-guard.ts"
[[ -r $script ]] || exit 0

shfmt_bin="$(command -v shfmt)" || exit 0
command -v deno >/dev/null 2>&1 || exit 0

projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
[[ -d $projects ]] || exit 0

exec deno run \
  --no-prompt \
  --allow-run="$shfmt_bin" \
  --allow-read="$projects" \
  "$script" "$shfmt_bin" "$projects"
