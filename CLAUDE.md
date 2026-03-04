# Dotfiles

Nix + Home Manager (with Flakes) で macOS/Linux のシェル・ツール設定を宣言的に管理するリポジトリ。macOS では nix-darwin を使用。

## Apply Changes

```bash
# Linux/WSL
home-manager switch --flake . --impure

# macOS (nix-darwin)
darwin-rebuild switch --flake . --impure

# Update packages
nix flake update
```
