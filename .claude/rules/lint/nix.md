---
paths:
  - "*.nix"
  - nix/**
  - flake.nix
---

```bash
alejandra .              # Format Nix files
statix check .           # Lint Nix files
deadnix .                # Find dead code in Nix files
```
