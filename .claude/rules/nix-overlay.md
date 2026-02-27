---
paths:
  - nix/overlays/default.nix
  - .github/workflows/update-nix-hashes.yml
---

npm-related flags or dependency workarounds for overlay packages must be applied to both:

1. `.github/workflows/update-nix-hashes.yml` - lock file generation in CI
2. `nix/overlays/default.nix` - `buildNpmPackage` npmFlags

These are two separate `npm install` invocations for the same package.
