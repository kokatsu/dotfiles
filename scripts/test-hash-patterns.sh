#!/usr/bin/env bash
set -euo pipefail
workdir=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$workdir"' EXIT
deno test --no-prompt --allow-read="$(pwd),$workdir" --allow-write="$workdir" \
  --allow-run=git,nix-instantiate scripts/test-hash-updates.ts -- "$workdir"
