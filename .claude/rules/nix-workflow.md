---
paths:
  - "*.nix"
  - nix/**
  - flake.*
  - .config/**
---

## Home Manager Workflow

- **Never edit Home Manager managed paths directly** (`~/.config/`, `~/.claude/` etc.) — add `xdg.configFile` or `home.file` entries in `nix/home/files.nix` (or the tool's `nix/home/programs/*.nix`) so Home Manager manages the symlink. After changes, remind the user to run `home-manager switch` (both Linux and macOS; `darwin-rebuild switch` is only for `nix/darwin/` changes).
- **Nix manages all packages** — add packages to `nix/home/packages.nix`, not with `brew install` or manual downloads.
- **`nix/home/` is the source of truth** for all CLI tools and dotfile symlinks: `packages.nix` for packages, `files.nix` and `programs/*.nix` for symlinks and generated config, `default.nix` only wires the modules together.
