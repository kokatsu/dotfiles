#!/bin/bash
CONFIG_DIRS="${CLAUDE_CONFIG_DIR:-$HOME/.claude},$HOME/.config/claude"
exec deno run --allow-read="$CONFIG_DIRS" \
  --allow-write="$CONFIG_DIRS" \
  --allow-env=HOME,CLAUDE_CONFIG_DIR \
  "$@"
