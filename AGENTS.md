# Dotfiles

Nix + Home Manager (with Flakes) で macOS/Linux のシェル・ツール設定を宣言的に管理するリポジトリ。macOS では nix-darwin を使用。

## Layout

- `nix/home/` — Home Manager 設定 (packages, dotfile symlinks の source of truth)
- `nix/darwin/` — nix-darwin 設定 (macOS のみ)
- `nix/overlays/` — カスタムパッケージ・ビルド修正
- `.config/` — 各ツールの設定ファイル (Home Manager が symlink で配置)
- `.codex/rules/*.rules` — このリポジトリ専用の Codex コマンド承認ルール

## Apply Changes

`--impure` は flake が `USER`/`HOSTNAME`/`PWD` を環境変数から読むため必須。

```bash
# Linux/WSL
home-manager switch --flake . --impure

# macOS (nix-darwin)
sudo HOSTNAME=$(hostname -s) darwin-rebuild switch --flake . --impure

# Update packages
nix flake update
```

## Local Checks

`just check` で fmt-check / lint / typos を一括実行、`just fmt` で整形。
commit 時は lefthook が自動で整形・lint・gitleaks を走らせる。
