{
  pkgs,
  lib,
  config,
  inputs,
  nodePackages,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  system = pkgs.stdenv.hostPlatform.system;
in {
  imports = [
    ./programs/bat.nix
    ./programs/eza.nix
    ./programs/fzf.nix
    ./programs/git.nix
    ./programs/starship.nix
    ./programs/zoxide.nix
    ./programs/zsh.nix
  ];

  home = {
    stateVersion = "24.11";

    packages = with pkgs; [
      # CLIツール
      bat
      btop
      curl
      delta
      eza
      fastfetch
      fd
      fzf
      gh
      git
      jq
      lazydocker
      lazygit
      ripgrep
      vivid
      wget
      yazi

      # 開発ツール
      bun
      claude-code
      deno
      nil # Nix LSP
      nixd
      alejandra # Nix formatter
      typos

      # Git hooks/lint ツール (Nixpkgs)
      biome
      lefthook

      # Git hooks/lint ツール (node2nix)
      nodePackages.nodeDependencies

      # Neovim nightly (overlay適用済み)
      neovim

      # ターミナル (flake inputからnightly)
      inputs.wezterm.packages.${system}.default
      # Ghostty: macOS未サポートのため手動インストール

      # エディタ
      vscode
    ];

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      XDG_CONFIG_HOME = "${config.home.homeDirectory}/.config";
      ZDOTDIR = "${config.xdg.configHome}/zsh";
      BAT_CONFIG_DIR = "${config.xdg.configHome}/bat";
      PSQLRC = "${config.xdg.configHome}/pg/.psqlrc";
      RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/.ripgreprc";
    };

    # .config へのシンボリックリンク
    file = {
      ".config/nvim".source = ../. + "/.config/nvim";
      ".config/bat".source = ../. + "/.config/bat";
      ".config/btop".source = ../. + "/.config/btop";
      ".config/delta".source = ../. + "/.config/delta";
      ".config/fastfetch".source = ../. + "/.config/fastfetch";
      ".config/git-graph".source = ../. + "/.config/git-graph";
      ".config/pg".source = ../. + "/.config/pg";
      ".config/wezterm".source = ../. + "/.config/wezterm";
    };
  };

  xdg.enable = true;

  programs.home-manager.enable = true;
}
