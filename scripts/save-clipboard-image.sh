#!/usr/bin/env bash
set -euo pipefail

directory="$(git rev-parse --show-toplevel)/.kokatsu/clipboard"
mkdir -p "$directory"

image=$(mktemp --suffix=.png "$directory/$(date +%Y%m%d-%H%M%S)-XXXXXX")
trap 'rm -f "$image"' ERR
# WSLg は Windows でコピーした画像を Wayland 側に image/bmp でしか渡さない
wl-paste --type image/bmp | magick bmp:- "png:$image"
printf '%s\n' "$image"
