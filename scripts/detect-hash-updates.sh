#!/usr/bin/env bash
set -euo pipefail
exec deno run --no-prompt --allow-read=. --allow-run=git \
  "$(dirname "${BASH_SOURCE[0]}")/update-hashes.ts" detect "${1:?usage: $0 <base-ref>}"
