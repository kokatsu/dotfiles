#!/bin/sh
# initializeCommand としてホストで動く。devcontainer.json が読み取り専用で bind する元が無いとコンテナが起動しないため、
# 無いものだけを、読み込む側が受け付ける空の設定で作る。既にあるものには触れない。
set -eu
cd "$(dirname "$0")/.."

file() {
  if [ -L "$1" ] && [ ! -e "$1" ]; then
    echo "ensure-bind-sources: $1 is a broken symlink" >&2
    exit 1
  elif [ -e "$1" ]; then
    if [ ! -f "$1" ]; then
      echo "ensure-bind-sources: $1 exists but is not a regular file" >&2
      exit 1
    fi
  else
    printf '%s\n' "$2" >"$1"
    echo "ensure-bind-sources: created $1"
  fi
}

dir() {
  if [ -e "$1" ] && [ ! -d "$1" ]; then
    echo "ensure-bind-sources: $1 exists but is not a directory" >&2
    exit 1
  fi
  mkdir -p "$1"
}

file .lefthook-local.jsonc '{}'
file .gitleaks.local.toml ''
file .claude/settings.local.json '{}'
file .config/nvim/lua/plugins/snacks/exclude.lua 'return {}'
file .config/wezterm/backgrounds.lua 'return {}'
dir .config/zsh/config.d
dir .config/zsh/functions.d
