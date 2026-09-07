---
paths:
  - nix/overlays/npm-packages.nix
  - .github/workflows/pr.yml
---

When an npm-based overlay package requires special `npm install` flags (e.g., `--legacy-peer-deps` for vite-plus), those same flags must be applied to both:

1. `nix/overlays/npm-packages.nix` - `buildNpmPackage` `npmFlags`/`npmPackFlags`
2. `.github/workflows/pr.yml` - the corresponding `npm install --package-lock-only` step in the `update-hashes` job

These are two separate `npm install` invocations for the same package.
