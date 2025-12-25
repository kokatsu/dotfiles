-- https://github.com/nix-community/nixd
-- https://github.com/nix-community/nixd/blob/main/nixd/docs/configuration.md

---@type vim.lsp.Config
return {
  settings = {
    nixd = {
      nixpkgs = {
        expr = 'import <nixpkgs> {}',
      },
      formatting = {
        command = { 'alejandra' },
      },
    },
  },
}
