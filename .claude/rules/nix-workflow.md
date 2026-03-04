---
paths:
  - "*.nix"
  - nix/**
  - flake.*
  - .config/**
---

## Home Manager Workflow

- **Never edit Home Manager managed paths directly** (`~/.config/`, `~/.claude/` etc.) — add `xdg.configFile` or `home.file` entries in `nix/home/default.nix` so Home Manager manages the symlink. After changes, remind the user to run `home-manager switch` (or `darwin-rebuild switch` on macOS).
- **Nix manages all packages** — add packages to `nix/home/default.nix`, not with `brew install` or manual downloads.
- **`nix/home/default.nix` is the source of truth** for all CLI tools and dotfile symlinks.
