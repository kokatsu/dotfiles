---
paths:
  - "*.lua"
  - .config/nvim/**
  - .config/wezterm/**
---

```bash
stylua .                 # Format Lua files
selene --config .config/nvim/selene.toml .config/nvim/  # Lint nvim config
selene --config .config/wezterm/selene.toml .config/wezterm/  # Lint wezterm config
```
