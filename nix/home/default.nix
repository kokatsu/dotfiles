{
  pkgs,
  lib,
  config,
  inputs,
  username ? "user",
  dotfilesDir ? "",
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  isWSL =
    !isCI
    && pkgs.stdenv.isLinux
    && (
      builtins.getEnv "WSL_DISTRO_NAME"
      != ""
      || builtins.getEnv "WSL_INTEROP" != ""
    );
  validDotfilesDir =
    if isCI
    then "/tmp/dotfiles"
    else if dotfilesDir == ""
    then throw "dotfilesDir is empty. Set DOTFILES_DIR or run from the repository root with --impure."
    else if !lib.hasPrefix "/" dotfilesDir
    then throw "dotfilesDir (${dotfilesDir}) must be an absolute path."
    else if !builtins.pathExists "${dotfilesDir}/flake.nix"
    then throw "dotfilesDir (${dotfilesDir}) is not the repository root. Set DOTFILES_DIR to the absolute dotfiles path."
    else dotfilesDir;
  homeDir =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
in {
  # dotfiles の実パスと実行環境を各ツールの module に共有する。
  _module.args = {
    inherit isWSL validDotfilesDir;
  };

  imports = [
    ./catppuccin-palette.nix
    ./packages.nix
    ./files.nix
    ./activation.nix
    ./programs/bat.nix
    ./programs/broot.nix
    ./programs/btop.nix
    ./programs/claude-code.nix
    ./programs/codex.nix
    ./programs/eza.nix
    ./programs/fzf.nix
    ./programs/gh.nix
    ./programs/git.nix
    ./programs/herdr.nix
    ./programs/hunk.nix
    ./programs/karabiner.nix
    ./programs/lazygit.nix
    ./programs/lefthook.nix
    ./programs/nh.nix
    ./programs/playwright.nix
    ./programs/readline.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    ./programs/wezterm.nix
    ./programs/zoxide.nix
    ./programs/zsh.nix
    ./services/feed-watch.nix
    ./themes/claude-code.nix
    ./themes/hermes.nix
  ];

  catppuccin = {
    enable = true;
    # port 自動有効化フラグ。enable の現行値 (true) を明示して移行警告を抑制。
    # release 27.05 以降は port の enable デフォルトが autoEnable 基準に切り替わる。
    autoEnable = true;
    flavor = "mocha";
    accent = "blue";

    # ポート生成に使う whiskers を nixpkgs の prebuilt 版に差し替える。
    # catppuccin/nix 同梱の whiskers は自前ビルド (= cache.nixos.org に無く毎回
    # ソースコンパイル) で、しかも nativeBuildInput のためランタイム closure に
    # 入らず GC されやすい → ポート再ビルドのたびに再コンパイルされ switch が遅い。
    # nixpkgs の catppuccin-whiskers は同 2.9.0 でバイナリキャッシュ済み。
    sources = let
      base = inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system};
      # whiskers だけ nixpkgs 版に差し替えた buildCatppuccinPort。
      fastBuild = base.buildCatppuccinPort.override {
        whiskers = pkgs.catppuccin-whiskers;
      };
    in
      base
      // builtins.mapAttrs (
        name: drv:
        # buildCatppuccinPort 製ポートは whiskersTemplates 属性を持つ。
          if !(lib.isDerivation drv && drv ? whiskersTemplates)
          then drv
          # pkgs/<port> 由来 (override 可) は引数だけ差し替えて固有設定を維持。
          else if drv ? override
          then
            drv.override (old:
              (lib.optionalAttrs (old ? buildCatppuccinPort) {buildCatppuccinPort = fastBuild;})
              // (lib.optionalAttrs (old ? whiskers) {whiskers = pkgs.catppuccin-whiskers;}))
          # sources.json のみ由来 (override なし) は fast 版で同名ポートを再生成。
          else fastBuild {port = name;}
      )
      base;
    # 既存 symlink と競合するため後の Phase で有効化
    delta.enable = false;
    # 手動管理 or カスタムテンプレートで管理
    nvim.enable = false;
    ghostty.enable = false;
    wezterm.enable = false;
    yazi.enable = false;
  };

  programs.home-manager.enable = true;

  # オフライン man (home-configuration.nix) の doc ビルドを無効化。
  # HM の scrubDerivations が context なしの nixpkgs source パスを options.json
  # に焼き込み "without a proper context" 警告を出すのを止める。Web マニュアルは無影響。
  manual.manpages.enable = false;

  home = {
    inherit username;
    homeDirectory = homeDir;
    stateVersion = "24.11";

    # nixpkgs-unstable (26.11) + home-manager master (release.json は 26.05 のまま)
    # を意図的に追従しているため、両者のリリース番号一致チェックは常に警告を出す。
    # upstream の home-manager が release.json を 26.11 にバンプしたら削除可。
    enableNixpkgsReleaseCheck = false;

    # PATH に追加 (ユーザースクリプト)
    sessionPath = [
      "${config.home.homeDirectory}/.local/bin/scripts"
      "${config.home.homeDirectory}/.local/share/pnpm/bin" # pnpm グローバルバイナリ (v11+ は bin/ サブディレクトリ)
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
        HERMES_HOME = "${config.xdg.configHome}/hermes";
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
      }
      // lib.optionalAttrs isDarwin {
        # LDC (D言語コンパイラ) とNix clang-wrapperの互換性のため
        # arm64-apple-darwinトリプルを指定してcc-wrapperとの不一致警告を回避
        DFLAGS = "-mtriple=arm64-apple-darwin";
      }
      // lib.optionalAttrs (!isDarwin) {
        # Nix 版 bun/node で npm プレビルト native モジュール (sharp 等) が
        # libstdc++.so.6 を解決できない問題の回避 (Linux のみ)
        LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib];
      };
  };

  xdg.enable = true;
  fonts.fontconfig.enable = true;
}
