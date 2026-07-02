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
          expr = '(let sudoUser = builtins.getEnv "SUDO_USER"; username = builtins.getEnv "USER"; user = if sudoUser != "" then sudoUser else if username == "" || username == "root" then "user" else username; in (builtins.getFlake ("git+file://" + toString ./.)).homeConfigurations.${user}.options)',
        },
      },
      formatting = {
        command = { 'alejandra' },
      },
    },
  },
}
