#!/bin/bash
query=$(cat | jq -r '.query')
cd "${CLAUDE_PROJECT_DIR:-.}"

fd --type f \
  --exclude node_modules \
  --exclude .git \
  --exclude dist \
  --exclude build \
  --exclude .next \
  --exclude coverage \
  --hidden \
  "$query" \
  2>/dev/null | head -15
