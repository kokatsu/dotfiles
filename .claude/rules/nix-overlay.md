---
paths:
  - nix/overlays/npm-packages.nix
  - scripts/hash-update-lib.ts
---

When an npm-based overlay package requires special `npm install` flags (e.g., `--legacy-peer-deps` for vite-plus), those same flags must be applied to both:

1. `nix/overlays/npm-packages.nix` - `buildNpmPackage` `npmFlags`/`npmPackFlags`
2. `scripts/hash-update-lib.ts` - the package's `npmFlags` entry, which `scripts/update-hashes.ts` passes to `npm install --package-lock-only` when it regenerates the lockfile on a Renovate PR

These are two separate `npm install` invocations for the same package.
