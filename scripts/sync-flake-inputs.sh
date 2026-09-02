#!/usr/bin/env bash
# sync-flake-inputs.sh — Renovate が flake.nix の URL を新タグに書き換えた input を検出し、
# `nix flake update` で flake.lock を同期する。
#
# Usage: bash scripts/sync-flake-inputs.sh <github_output_path>
#
# 対象: `<name> = { url = "..."; ... }` のブロック形式 input のみ
# (nixpkgs.url 等の短形式は対象外)

set -euo pipefail

GITHUB_OUTPUT_FILE="$1"

git fetch origin main

if git diff --quiet origin/main -- flake.nix; then
  echo "No flake.nix changes; skipping flake.lock sync" >&2
  echo "extra_packages=" >>"$GITHUB_OUTPUT_FILE"
  exit 0
fi

HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-flake-input-urls.ts"

parse_inputs() {
  # ヘルパーは stdin しか読まないので Deno の権限フラグは不要
  deno run --no-prompt "$HELPER" <"$1"
}

OLD_FLAKE=$(mktemp)
trap 'rm -f "$OLD_FLAKE"' EXIT
git show origin/main:flake.nix >"$OLD_FLAKE"

declare -A NEW_URLS OLD_URLS
while IFS=' ' read -r name url; do
  NEW_URLS[$name]="$url"
done < <(parse_inputs flake.nix)

while IFS=' ' read -r name url; do
  OLD_URLS[$name]="$url"
done < <(parse_inputs "$OLD_FLAKE")

CHANGED=()
EXTRA=""
for input in "${!NEW_URLS[@]}"; do
  if [[ "${NEW_URLS[$input]}" != "${OLD_URLS[$input]:-}" ]]; then
    NEW_TAG="${NEW_URLS[$input]##*/}"
    # Validate to prevent shell injection via crafted URL ref.
    if [[ ! "$NEW_TAG" =~ ^[0-9a-zA-Z.+_-]+$ ]]; then
      echo "::error::Invalid tag format for $input: $NEW_TAG" >&2
      exit 1
    fi
    echo "Syncing $input: '${OLD_URLS[$input]:-<new>}' -> '${NEW_URLS[$input]}'" >&2
    CHANGED+=("$input")
    EXTRA="${EXTRA:+$EXTRA, }$input $NEW_TAG"
  fi
done

if [ ${#CHANGED[@]} -gt 0 ]; then
  nix flake update "${CHANGED[@]}"
fi

echo "extra_packages=$EXTRA" >>"$GITHUB_OUTPUT_FILE"
