# Dotfiles

Nix + Home Manager (with Flakes) で macOS/Linux のシェル・ツール設定を宣言的に管理するリポジトリ。ユーザー環境は両 OS とも standalone の Home Manager で管理し、macOS のシステム設定と Homebrew のみ nix-darwin で管理する。

## Layout

- `nix/home/` — Home Manager 設定 (packages, dotfile symlinks の source of truth)
- `nix/darwin/` — nix-darwin 設定 (macOS のみ)
- `nix/overlays/` — カスタムパッケージ・ビルド修正
- `.config/` — 各ツールの設定ファイル (Home Manager が symlink で配置)
- `.codex/rules/*.rules` — このリポジトリ専用の Codex コマンド承認ルール

## Apply Changes

`--impure` は flake が `USER`/`HOSTNAME`/`PWD` を環境変数から読むため必須。

```bash
# ユーザー環境 (packages / dotfiles)。Linux/WSL と macOS 共通
home-manager switch --flake . --impure

# macOS システム設定 + Homebrew。cask の upgrade が走るため Chrome を閉じてから実行
sudo HOSTNAME=$(hostname -s) darwin-rebuild switch --flake . --impure

# Update packages
nix flake update
```

## Local Checks

`just check` で fmt-check / lint / typos を一括実行、`just fmt` で整形。
commit 時は lefthook が自動で整形・lint・gitleaks を走らせる。
