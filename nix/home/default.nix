{
  pkgs,
  lib,
  config,
  inputs,
  self,
  nodePackages,
  stablePkgs,
  username ? "user",
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  system = pkgs.stdenv.hostPlatform.system;
  isX86_64 = builtins.elem system ["x86_64-linux" "x86_64-darwin"];
  homeDir =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
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
    username = username;
    homeDirectory = homeDir;
    stateVersion = "24.11";

    packages = with pkgs;
      [
        # ランタイム (グローバルデフォルト)
        go
        nodejs_24
        pnpm
        stablePkgs.ruby_3_1 # nixpkgs-stable (24.05) から取得
        rustup

        # CLIツール
        bat
        btop
        chafa # 画像→テキスト
        curl
        delta
        eza
        fastfetch
        fd
        figlet # ASCIIアート
        fzf
        gh
        git
        git-graph
        helix
        jq
        lazydocker
        lazygit
        nb # ノート管理
        nmap # ネットワーク
        ov # ページャー
        ripgrep
        scc # コード統計
        tig # Git TUI
        vivid
        w3m # テキストブラウザ
        wget
        yazi
        zimfw # Zsh framework

        # メディア/画像処理
        cava # 音声ビジュアライザ
        cfonts # ASCIIアート
        imagemagick
        imgcat # 画像表示
        tesseract # OCR
        ueberzugpp # 画像表示
        vips # 画像処理

        # ドキュメント
        pandoc

        # その他言語/ツール
        zig
      ]
      ++ lib.optionals isX86_64 [
        # D言語コンパイラ (dmdはx86_64のみ対応)
        dmd
      ]
      ++ [
        # D言語ツール (arm64対応)
        ldc
        dub
        dformat
      ]
      ++ [
        # 開発ツール
        bun
        claude-code
        deno
        docker-compose
        pipx # Python CLI管理
        alejandra # Nix formatter
        stylua # Lua formatter
        typos

        # プレゼン
        presenterm

        # Spotify
        spotify-player

        # Language Servers
        astro-language-server
        copilot-language-server
        dockerfile-language-server
        lua-language-server
        nil # Nix LSP
        nixd
        svelte-language-server
        tailwindcss-language-server
        taplo # TOML LSP
        vscode-langservers-extracted # HTML/CSS/JSON/ESLint
        vtsls # TypeScript LSP
        vue-language-server
        yaml-language-server

        # Git hooks/lint ツール (Nixpkgs)
        biome
        lefthook

        # Git hooks/lint ツール (node2nix)
        nodePackages.nodeDependencies

        # Neovim nightly (overlay適用済み)
        neovim

        # フォント (Nerd Fonts)
        nerd-fonts.fira-code
        nerd-fonts.hack
        nerd-fonts.symbols-only
      ]
      ++ lib.optionals isDarwin [
        # macOS専用
        vscode

        # ターミナル (flake inputからnightly)
        # WSLではWindows側にインストールするためLinuxでは除外
        inputs.wezterm.packages.${system}.default
      ];

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      XDG_CONFIG_HOME = "${config.home.homeDirectory}/.config";
      ZDOTDIR = "${config.xdg.configHome}/zsh";
      BAT_CONFIG_DIR = "${config.xdg.configHome}/bat";
      CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
      PSQLRC = "${config.xdg.configHome}/pg/.psqlrc";
      RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/.ripgreprc";
      INPUTRC = "${config.xdg.configHome}/readline/inputrc";
      # node2nix でインストールした npm パッケージを解決するため
      NODE_PATH = "${nodePackages.nodeDependencies}/lib/node_modules";
    };

    # .config へのシンボリックリンク
    file = {
      ".config/nvim" = {
        source = ../../.config/nvim;
        recursive = true;
      };
      ".config/bat".source = ../../.config/bat;
      ".config/btop".source = ../../.config/btop;
      ".config/claude/settings.json".source = ../../.config/claude/settings.json;
      ".config/delta".source = ../../.config/delta;
      ".config/fastfetch".source = ../../.config/fastfetch;
      ".config/git-graph".source = ../../.config/git-graph;
      ".config/pg".source = ../../.config/pg;

      # WezTerm: 個別ファイルをリンク (backgroundsは別途リンク)
      ".config/wezterm/background.lua".source = ../../.config/wezterm/background.lua;
      ".config/wezterm/colors.lua".source = ../../.config/wezterm/colors.lua;
      ".config/wezterm/format.lua".source = ../../.config/wezterm/format.lua;
      ".config/wezterm/keybinds.lua".source = ../../.config/wezterm/keybinds.lua;
      ".config/wezterm/mac.lua".source = ../../.config/wezterm/mac.lua;
      ".config/wezterm/stylua.toml".source = ../../.config/wezterm/stylua.toml;
      ".config/wezterm/wezterm.lua".source = ../../.config/wezterm/wezterm.lua;
      ".config/wezterm/windows.lua".source = ../../.config/wezterm/windows.lua;

      # 新規追加
      ".config/yazi".source = ../../.config/yazi;
      ".config/gh".source = ../../.config/gh;
      ".config/helix".source = ../../.config/helix;
      ".config/lazydocker".source = ../../.config/lazydocker;
      ".config/lazygit".source = ../../.config/lazygit;
      ".config/readline".source = ../../.config/readline;
    };
  };

  xdg.enable = true;

  programs.home-manager.enable = true;

  # Home Manager 適用後に実行されるスクリプト
  home.activation = {
    fixNvimLockFile = lib.hm.dag.entryAfter ["linkGeneration"] ''
      # lazy-lock.json をコピーして書き込み可能にする
      if [ -L "$HOME/.config/nvim/lazy-lock.json" ]; then
        LOCK_TARGET=$(readlink "$HOME/.config/nvim/lazy-lock.json")
        $DRY_RUN_CMD rm "$HOME/.config/nvim/lazy-lock.json"
        $DRY_RUN_CMD cp "$LOCK_TARGET" "$HOME/.config/nvim/lazy-lock.json"
        $DRY_RUN_CMD chmod u+w "$HOME/.config/nvim/lazy-lock.json"
      fi
    '';

    setupNvimAssets = lib.hm.dag.entryAfter ["linkGeneration"] ''
      # Create a separate nvim-assets directory that's not managed by Nix
      if [ -d "${self}/.config/nvim/assets" ]; then
        $DRY_RUN_CMD mkdir -p "$HOME/.config/nvim-assets"
        $DRY_RUN_CMD cp -r "${self}/.config/nvim/assets/"* "$HOME/.config/nvim-assets/" 2>/dev/null || true
      fi
    '';
  };
}
