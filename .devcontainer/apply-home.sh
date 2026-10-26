#!/usr/bin/env bash
# Home Manager の devcontainer 構成 (nix/devcontainer/home.nix) をこのコンテナへ適用する。
# 取得が要るのは初回だけなので、ファイアウォールを張る前の postCreateCommand で走らせる。
# 起動後はファイアウォールが cache.nixos.org を塞ぐので、手で再実行するときは --offline を付ける。
# 引数は nix build へ渡す
set -euo pipefail

cd "$(dirname "$0")/.."
# Home Manager が ~/.claude をリンクにする。空のディレクトリが残っていれば消し、中身があれば止める
if [ -d ~/.claude ] && [ ! -L ~/.claude ]; then
  rmdir ~/.claude
fi
activation=$(DOTFILES_DIR="$PWD" nix build --no-link --print-out-paths --impure \
  "$@" .#homeConfigurations.devcontainer.activationPackage)
"$activation/activate"
