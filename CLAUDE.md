# Dotfiles

This is a dotfiles repository for managing shell and tool configurations across macOS and Linux systems using **Nix + Home Manager** with Flakes. It provides declarative, reproducible environment management with nix-darwin support for macOS.

## Key Commands

### Linting and Formatting

```bash
# Biome (JS/TS/JSON)
biome check --write .

# Nix
alejandra .              # Format Nix files
statix check .           # Lint Nix files
deadnix .                # Find dead code in Nix files

# Lua
stylua .                 # Format Lua files
selene --config .config/nvim/selene.toml .config/nvim/  # Lint nvim config
selene --config .config/wezterm/selene.toml .config/wezterm/  # Lint wezterm config

# YAML
yamlfmt .                # Format YAML files

# Typos
typos                    # Check for typos
```

### Environment Setup (Nix)

```bash
# Apply configuration changes (Linux/WSL)
home-manager switch --flake . --impure

# Apply configuration changes (macOS with nix-darwin)
darwin-rebuild switch --flake . --impure

# Update packages to latest versions
nix flake update
home-manager switch --flake . --impure
```

### Nix Development

```bash
# Enter development shell with Nix tools
nix develop

# Check flake configuration
nix flake check

# Show flake metadata
nix flake metadata
```

## Commit Message Convention

Follow Conventional Commits (`@commitlint/config-conventional`).

| Type | Usage |
|---|---|
| `feat` | New feature or functionality |
| `fix` | Bug fix |
| `build` | Build system or dependency changes (scope: `deps` for dependency updates) |
| `chore` | Configuration or maintenance (no feature/fix) |
| `refactor` | Code restructuring without behavior change |
| `style` | Formatting changes (no logic change) |
| `docs` | Documentation only |
| `ci` | CI configuration changes |
| `perf` | Performance improvements |
| `test` | Adding or fixing tests |

Key guidelines:

- Config file tweaks (e.g. renovate.json5, flake.nix settings) → `chore`, not `feat`
- Adding a new overlay or tool → `feat`
- Dependency version bumps → `build(deps)`

## Important Notes

- **Never edit Home Manager managed paths directly** (`~/.config/`, `~/.claude/` etc.) - If the tool's dotfile symlink is not yet configured in `nix/home/default.nix`, add the appropriate `xdg.configFile` or `home.file` entry so Home Manager manages the symlink. After changes, remind the user to run `home-manager switch` (or `darwin-rebuild switch` on macOS) to apply.
- **No TypeScript code in this repo** - TypeScript configuration exists but only for potential scripts, not for the dotfiles themselves
- **Nix manages all packages** - Add packages to `nix/home/default.nix`, not with `brew install` or manual downloads
- **nix/home/default.nix is the source of truth** - All CLI tools and dotfile symlinks are defined here
- **Secretlint is configured** - Prevents committing secrets (runs as part of pre-commit hooks)
- **nix-darwin for macOS** - Use `darwin-rebuild` instead of `home-manager` on macOS for full system integration
