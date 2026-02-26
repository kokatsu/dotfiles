# Dotfiles

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
