---
paths:
  - "**/*"
---

Follow Conventional Commits (`@commitlint/config-conventional`).

Project-specific guidelines:

- Config file tweaks (e.g. renovate.json5, flake.nix settings) → `chore`, not `feat`
- Adding a new overlay or tool → `feat`
- Dependency version bumps → `build(deps)`
