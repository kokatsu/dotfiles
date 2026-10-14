{pkgs, ...}: {
  xdg.configFile."kakehashi/kakehashi.toml".source = pkgs.kakehashi-config;
  home = {
    packages = [pkgs.neovim];
    sessionVariables.RUBY_LSP_COMMAND = "${pkgs.ruby-lsp}/bin/ruby-lsp";
    file = {
      ".local/share/nvim/nix-plugins/fff.nvim".source = pkgs.vimPlugins.fff-nvim;
      ".local/share/nvim/nix-plugins/peek.nvim".source = pkgs.peek-nvim;
      ".local/share/nvim/nix-plugins/lazy.nvim".source = pkgs.lazy-nvim;
      ".local/share/nvim/nix-plugins/blink.cmp".source = pkgs.vimPlugins.blink-cmp;
      ".local/share/nvim/nix-plugins/nvim-treesitter".source = pkgs.treesitter-nvim;
      ".local/share/nvim/nix-plugins/pkl-neovim".source = pkgs.pkl-neovim;
    };
  };
}
