# Third-Party Licenses

This document collects license notices for third-party works that are vendored
into this repository or whose values (color palettes, etc.) are embedded in
files in this repository.

Sub-trees that are independently distributable keep their own LICENSE files
and are not duplicated here:

- `.config/yazi/flavors/*/LICENSE` — yazi flavors are distributed per-directory via `ya pkg`
- `.config/yazi/plugins/*/LICENSE` — same as above
- `.config/zsh/.zim/modules/*/LICENSE` — zimfw modules are independent submodules

## Catppuccin

Files vendored from or embedding hex values derived from
[Catppuccin](https://github.com/catppuccin) projects:

| Path | Upstream |
| --- | --- |
| `.config/bat/themes/Catppuccin Frappe.tmTheme` | [catppuccin/bat](https://github.com/catppuccin/bat) |
| `.config/bat/themes/Catppuccin Latte.tmTheme` | [catppuccin/bat](https://github.com/catppuccin/bat) |
| `.config/bat/themes/Catppuccin Macchiato.tmTheme` | [catppuccin/bat](https://github.com/catppuccin/bat) |
| `.config/bat/themes/Catppuccin Mocha.tmTheme` | [catppuccin/bat](https://github.com/catppuccin/bat) |
| `.config/btop/themes/catppuccin_mocha.theme` | [catppuccin/btop](https://github.com/catppuccin/btop) |
| `.config/delta/catppuccin.gitconfig` | [catppuccin/delta](https://github.com/catppuccin/delta) |
| `.config/lazygit/catppuccin-mocha-blue.yml` | [catppuccin/lazygit](https://github.com/catppuccin/lazygit) |
| `nix/home/catppuccin-palette.nix` | [catppuccin/palette](https://github.com/catppuccin/palette) |
| `tools/cc-statusline/src/output.zig` (color values in `theme_catppuccin_*`) | [catppuccin/palette](https://github.com/catppuccin/palette) |

```text
MIT License

Copyright (c) 2021 Catppuccin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## WezTerm

File vendored from [wez/wezterm](https://github.com/wez/wezterm):

| Path | Upstream |
| --- | --- |
| `.config/zsh/wezterm-integration.sh` | [wez/wezterm `assets/shell-integration/wezterm.sh`](https://github.com/wez/wezterm/blob/main/assets/shell-integration/wezterm.sh) |

```text
MIT License

Copyright (c) 2018-Present Wez Furlong

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
