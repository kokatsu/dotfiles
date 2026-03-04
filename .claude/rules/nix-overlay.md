---
paths:
  - nix/overlays/default.nix
  - .github/workflows/update-nix-hashes.yml
---

When an npm-based overlay package requires special `npm install` flags (e.g., `--legacy-peer-deps` for agent-browser), those same flags must be applied to both:

1. `nix/overlays/default.nix` - `buildNpmPackage` `npmFlags`/`npmPackFlags`
2. `.github/workflows/update-nix-hashes.yml` - the corresponding `npm install --package-lock-only` step

These are two separate `npm install` invocations for the same package.
