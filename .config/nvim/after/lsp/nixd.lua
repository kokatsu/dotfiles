-- https://github.com/nix-community/nixd
-- https://github.com/nix-community/nixd/blob/main/nixd/docs/configuration.md

---@type vim.lsp.Config
return {
  settings = {
    nixd = {
      nixpkgs = {
        expr = 'import (builtins.getFlake ("git+file://" + toString ./.)).inputs.nixpkgs {}',
      },
      formatting = {
        command = { 'alejandra' },
      },
    },
  },
}
