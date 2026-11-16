#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd "$repo_root/tools/agent-hooks/agent-guard" && go build -o "$work/agent-guard" .)
PATH="$work:$PATH" node --test "$repo_root/.config/pi/extensions/agent-guard.test.ts"
