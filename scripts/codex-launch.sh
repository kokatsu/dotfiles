#!/usr/bin/env bash
set -euo pipefail

codex_bin=$1
shift

# Shared servers retain the launching terminal's HERDR_* environment.
if [[ ${HERDR_ENV:-} == 1 ]]; then
  for arg in "$@"; do
    case $arg in
    --no-daemon | --remote | --remote=*) exec "$codex_bin" "$@" ;;
    --) break ;;
    esac
  done
  set -- --no-daemon "$@"
fi

exec "$codex_bin" "$@"
