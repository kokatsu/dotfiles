{
  pkgs,
  lib,
  config,
  username ? "user",
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  homeDir =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
in {
  imports = [
    ./catppuccin-palette.nix
    ./packages.nix
    ./files.nix
    ./activation.nix
    ./programs/bat.nix
    ./programs/btop.nix
    ./programs/eza.nix
    ./programs/fzf.nix
    ./programs/gh.nix
    ./programs/git.nix
    ./programs/lazygit.nix
    ./programs/readline.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    ./programs/zoxide.nix
    ./programs/zsh.nix
    ./services/feed-watch.nix
  ];

  catppuccin = {
    enable = true;
    flavor = "mocha";
    accent = "blue";
    # 既存 symlink と競合するため後の Phase で有効化
    delta.enable = false;
    # 手動管理 or カスタムテンプレートで管理
    nvim.enable = false;
    ghostty.enable = false;
    wezterm.enable = false;
    yazi.enable = false;
  };

  programs.home-manager.enable = true;

  home = {
    inherit username;
    homeDirectory = homeDir;
    stateVersion = "24.11";

    # PATH に追加 (ユーザースクリプト)
    sessionPath = [
      "${config.home.homeDirectory}/.local/bin/scripts"
      "${config.home.homeDirectory}/.local/share/pnpm" # pnpm グローバルバイナリ
      "${config.home.homeDirectory}/.gem/bin" # ruby-lsp 等の gem 実行ファイル
    ];

    sessionVariables =
      {
        PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";
        EDITOR = "nvim";
        VISUAL = "nvim";
        GEM_HOME = "${config.home.homeDirectory}/.gem"; # gem インストール先 (バージョン非依存)
        XDG_CONFIG_HOME = "${config.home.homeDirectory}/.config";
        ZDOTDIR = "${config.xdg.configHome}/zsh";
        BAT_CONFIG_DIR = "${config.xdg.configHome}/bat";
        CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
        PSQLRC = "${config.xdg.configHome}/pg/.psqlrc";
        RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/.ripgreprc";
        CODEX_HOME = "${config.xdg.configHome}/codex";
        TERMFRAME_CONFIG = "${config.xdg.configHome}/termframe/config.toml";
        TAPLO_CONFIG = "${config.xdg.configHome}/taplo/taplo.toml";
        CATPPUCCIN_VIVID_THEME = "catppuccin-${config.catppuccin.flavor}";
        CC_STATUSLINE_THEME = "catppuccin-${config.catppuccin.flavor}";
        CATPPUCCIN_NVIM_FLAVOR = config.catppuccin.flavor;
        CATPPUCCIN_NVIM_LIGHT_FLAVOR = "latte";
        # Catppuccin flavor から appearance を導出 (latte だけ light、それ以外は dark)
        APPEARANCE =
          if config.catppuccin.flavor == "latte"
          then "light"
          else "dark";
        # Playwright ブラウザパス (Nix管理)
        PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      }
      // lib.optionalAttrs isDarwin {
        # LDC (D言語コンパイラ) とNix clang-wrapperの互換性のため
        # arm64-apple-darwinトリプルを指定してcc-wrapperとの不一致警告を回避
        DFLAGS = "-mtriple=arm64-apple-darwin";
      }
      // lib.optionalAttrs (!isDarwin) {
        # playwright-cli (MCP) がChromeを見つけるためのパス
        # Nix管理のGoogle ChromeはLinuxの標準パス (/opt/google/chrome/chrome) にないため必要
        PLAYWRIGHT_MCP_EXECUTABLE_PATH = "${pkgs.google-chrome}/bin/google-chrome-stable";
      };
  };

  xdg.enable = true;

  # 不要なNixストアを自動削除 (週1回、7日以上前のものを削除)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
}
