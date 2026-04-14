-- https://github.com/nix-community/nixd
-- https://github.com/nix-community/nixd/blob/main/nixd/docs/configuration.md

---@type vim.lsp.Config
return {
  settings = {
    nixd = {
      nixpkgs = {
        expr = 'import (builtins.getFlake ("git+file://" + toString ./.)).inputs.nixpkgs {}',
      },
      -- home-manager モジュールのオプション補完 (catppuccin.flavor 等の候補表示に使用)
      options = {
        ['home-manager'] = {
          expr = '(builtins.getFlake ("git+file://" + toString ./.)).homeConfigurations.komai.options',
        },
      },
      formatting = {
        command = { 'alejandra' },
      },
    },
  },
}
