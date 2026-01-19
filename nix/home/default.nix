{
  pkgs,
  lib,
  config,
  inputs,
  nodePackages,
  stablePkgs,
  dotfilesDir ? "",
  username ? "user",
  isCI ? false, # CI環境フラグ
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.stdenv.hostPlatform) system;
  homeDir =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # dotfilesDirが空の場合はエラーを出す（--impureフラグ忘れ防止）
  # CI環境ではスキップ
  validDotfilesDir =
    if isCI
    then "/tmp/dotfiles" # CI用ダミーパス
    else if dotfilesDir == ""
    then throw "dotfilesDir is empty. Did you forget --impure flag?"
    else dotfilesDir;
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
    inherit username;
    homeDirectory = homeDir;
    stateVersion = "24.11";

    packages = with pkgs;
      [
        # agent-browser: node2nixのバイナリパスを修正するラッパー (hiPrioで競合解決)
        (lib.hiPrio (writeShellScriptBin "agent-browser" ''
          exec ${nodePackages.nodeDependencies}/lib/node_modules/agent-browser/bin/agent-browser-${
            if stdenv.isDarwin
            then "darwin"
            else "linux"
          }-${
            if stdenv.hostPlatform.isAarch64
            then "arm64"
            else "x64"
          } "$@"
        ''))
        # ランタイム (グローバルデフォルト)
        go
        nodejs_24
        pnpm
        stablePkgs.ruby_3_1 # nixpkgs-stable (24.05) から取得
        rustup

        # Playwright (ブラウザ自動化)
        playwright-driver

        # CLIツール
        fontconfig # フォント管理 (fc-list等)
        _7zz # 7-Zip アーカイバ
        mise # ランタイム管理
        bat
        btop
        chafa # 画像→テキスト
        curl
        delta
        duckdb # OLAP DB
        eza
        fastfetch
        fd
        figlet # ASCIIアート
        fzf
        gh
        git
        graphviz # グラフ可視化
        helix
        jq
        miller # CSV/JSON処理
        lazydocker
        lazygit
        nb # ノート管理
        nmap # ネットワーク
        ov # ページャー
        ripgrep
        scc # コード統計
        termshot # ターミナルスクリーンショット (PNG)
        tig # Git TUI
        treemd # Markdown navigator TUI
        tree-sitter # Treesitter CLI (nvim-treesitter パーサービルド用)
        vivid
        w3m # テキストブラウザ
        wget
        xleak # Excel TUI viewer
        yazi
        zellij # ターミナルマルチプレクサ
        zimfw # Zsh framework

        # メディア/画像処理
        ffmpegthumbnailer # 動画サムネイル (yazi プレビュー用)
        cava # 音声ビジュアライザ
        cfonts # ASCIIアート
        imagemagick
        imgcat # 画像表示
        jp2a # JPG→ASCII変換
        libcaca # テキストグラフィックス
        potrace # ビットマップ→ベクター変換
        tesseract # OCR
        ueberzugpp # 画像表示
        vips # 画像処理

        # ドキュメント
        ghostscript
        pandoc
        poppler-utils # PDF操作ツール (pdftotext, pdfimages等)

        # その他言語/ツール
        coursier # Scala依存関係管理
        luarocks # Luaパッケージマネージャ
        zig
      ]
      ++ lib.optionals (!isCI) [
        # D言語ツール (CI ではビルドが失敗するためスキップ)
        ldc
        dub
        dformat
        dtools # rdmd, dustmite など
      ]
      ++ [
        # 開発ツール
        bun
        # claude-code は nodePackages.package で管理
        gitleaks # シークレット検出
        deno
        docker-compose
        pipx # Python CLI管理
        alejandra # Nix formatter
        statix # Nix linter
        deadnix # Nix dead code finder
        stylua # Lua formatter
        selene # Lua linter
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
        vue-language-server # 3.0.8 - overlay でピン留め
        yaml-language-server

        # Git hooks/lint ツール (Nixpkgs)
        biome
        lefthook

        # Git hooks/lint ツール (node2nix)
        nodePackages.nodeDependencies
        nodePackages.package # CLIバイナリ (claude-code等)
      ]
      ++ lib.optionals (!isCI) [
        # CI ではスキップ (ビルド時間短縮)
        # Go 製パッケージ
        deck-slides # Markdown → Google Slides

        # Rust 製パッケージ
        git-graph
        termframe # ターミナルスクリーンショット (SVG, Nerd Font対応)

        # Neovim nightly (overlay適用済み、ソースビルド)
        neovim

        # フォント (Nerd Fonts、ダウンロードが大きい)
        nerd-fonts.fira-code
        nerd-fonts.hack
        nerd-fonts.symbols-only
      ]
      ++ lib.optionals isDarwin [
        # macOS専用
        terminal-notifier # macOS通知
      ]
      ++ lib.optionals (!isDarwin) [
        # Linux/WSL専用
        google-chrome
        noto-fonts-cjk-sans # 日本語フォント
      ]
      ++ lib.optionals (isDarwin && !isCI) [
        # macOS専用 (CI ではスキップ)
        vscode

        # ターミナル (WezTerm nightly)
        # Ghostty は Homebrew cask で管理 (nix/darwin/default.nix)
        # WSLではWindows側にインストールするためLinuxでは除外
        inputs.wezterm.packages.${system}.default
      ];

    sessionVariables =
      {
        EDITOR = "nvim";
        VISUAL = "nvim";
        XDG_CONFIG_HOME = "${config.home.homeDirectory}/.config";
        ZDOTDIR = "${config.xdg.configHome}/zsh";
        BAT_CONFIG_DIR = "${config.xdg.configHome}/bat";
        CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
        PSQLRC = "${config.xdg.configHome}/pg/.psqlrc";
        RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/.ripgreprc";
        INPUTRC = "${config.xdg.configHome}/readline/inputrc";
        TERMFRAME_CONFIG = "${config.xdg.configHome}/termframe/config.toml";
        # node2nix でインストールした npm パッケージを解決するため
        NODE_PATH = "${nodePackages.nodeDependencies}/lib/node_modules";
        # Playwright ブラウザパス (Nix管理)
        PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      }
      // lib.optionalAttrs isDarwin {
        # LDC (D言語コンパイラ) とNix clang-wrapperの互換性のため
        # arm64-apple-darwinトリプルを指定してcc-wrapperとの不一致警告を回避
        DFLAGS = "-mtriple=arm64-apple-darwin";
      };

    # .config へのシンボリックリンク
    file = {
      # nvim: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
      # これによりlazy-lock.jsonへの書き込みがリポジトリに反映される
      ".config/nvim" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/nvim";
        force = true;
      };
      ".config/bat".source = ../../.config/bat;
      ".config/btop" = {
        source = ../../.config/btop;
        force = true;
      };
      ".config/claude/settings.json".source = ../../.config/claude/settings.json;
      ".config/claude/skills".source = ../../.config/claude/skills;
      ".config/delta".source = ../../.config/delta;
      ".config/fastfetch".source = ../../.config/fastfetch;
      ".config/git-graph".source = ../../.config/git-graph;
      ".config/pg".source = ../../.config/pg;
      ".config/.ripgreprc".source = ../../.config/.ripgreprc;

      # WezTerm: 個別ファイルをリンク
      ".config/wezterm/background.lua".source = ../../.config/wezterm/background.lua;
      ".config/wezterm/colors.lua".source = ../../.config/wezterm/colors.lua;
      ".config/wezterm/format.lua".source = ../../.config/wezterm/format.lua;
      ".config/wezterm/keybinds.lua".source = ../../.config/wezterm/keybinds.lua;
      ".config/wezterm/mac.lua".source = ../../.config/wezterm/mac.lua;
      ".config/wezterm/stylua.toml".source = ../../.config/wezterm/stylua.toml;
      ".config/wezterm/wezterm.lua".source = ../../.config/wezterm/wezterm.lua;
      ".config/wezterm/windows.lua".source = ../../.config/wezterm/windows.lua;

      # 新規追加
      # Ghostty: 個別ファイルをリンク
      ".config/ghostty/config".source = ../../.config/ghostty/config;
      ".config/ghostty/themes/catppuccin-mocha".source = ../../.config/ghostty/themes/catppuccin-mocha;

      # yazi: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
      # これにより ya pkg コマンドで package.toml への書き込みが可能
      ".config/yazi" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/yazi";
        force = true;
      };
      # gh: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
      # hosts.yml は gh auth login で動的に作成されるため、ディレクトリではなくファイル単位でリンク
      ".config/gh/config.yml" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/gh/config.yml";
        force = true;
      };
      ".config/helix".source = ../../.config/helix;
      ".config/lazydocker".source = ../../.config/lazydocker;
      ".config/lazygit".source = ../../.config/lazygit;
      ".config/readline".source = ../../.config/readline;
      ".config/termframe".source = ../../.config/termframe;
      ".config/treemd".source = ../../.config/treemd; # XDG_CONFIG_HOME で解決
    };
  };

  xdg.enable = true;

  programs.home-manager.enable = true;

  # Home Manager 適用後に実行されるスクリプト
  home.activation = {
    # リンク作成前に衝突するディレクトリを削除
    removeConflictingDirs = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      # btop ディレクトリが実ディレクトリの場合は削除
      if [ -d "$HOME/.config/btop" ] && [ ! -L "$HOME/.config/btop" ]; then
        $DRY_RUN_CMD rm -rf "$HOME/.config/btop"
      fi
    '';
    # WSL2 で不要な PulseAudio サービスをマスク
    maskPulseAudio = lib.mkIf (!isDarwin) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user mask --now pulseaudio.service pulseaudio.socket 2>/dev/null || true
    '');

    # メディアファイル (背景画像、ロゴ) をコピー (git管理外)
    setupAssets = lib.hm.dag.entryAfter ["linkGeneration"] ''
      SOURCE="${dotfilesDir}/.config/assets"
      TARGET="$HOME/.config/assets"
      if [ -d "$SOURCE" ]; then
        $DRY_RUN_CMD mkdir -p "$TARGET/backgrounds" "$TARGET/logos"
        for subdir in backgrounds logos; do
          if [ -d "$SOURCE/$subdir" ]; then
            $DRY_RUN_CMD cp -r "$SOURCE/$subdir/"* "$TARGET/$subdir/" 2>/dev/null || true
          fi
        done
      fi
    '';

    # gh ディレクトリを作成
    # config.yml は mkOutOfStoreSymlink で管理、hosts.yml は gh auth login で動的に作成される
    fixGhDirectory = lib.hm.dag.entryAfter ["linkGeneration"] ''
      $DRY_RUN_CMD mkdir -p "$HOME/.config/gh"
    '';

    # Playwright ブラウザを Nix store からシンボリックリンク (agent-browser 用)
    # agent-browser は PLAYWRIGHT_BROWSERS_PATH を無視するため、デフォルトパスにリンクを作成
    setupPlaywrightBrowsers = lib.hm.dag.entryAfter ["linkGeneration"] ''
      PLAYWRIGHT_CACHE="${
        if isDarwin
        then "$HOME/Library/Caches/ms-playwright"
        else "$HOME/.cache/ms-playwright"
      }"
      PLAYWRIGHT_BROWSERS="${pkgs.playwright-driver.browsers}"
      $DRY_RUN_CMD mkdir -p "$PLAYWRIGHT_CACHE"
      for browser in "$PLAYWRIGHT_BROWSERS"/*; do
        name=$(basename "$browser")
        target="$PLAYWRIGHT_CACHE/$name"
        if [ -L "$target" ]; then
          $DRY_RUN_CMD rm "$target"
        fi
        $DRY_RUN_CMD ln -sf "$browser" "$target"
      done
    '';

    # btop ディレクトリを書き込み可能にする (btopが設定を書き込むため)
    fixBtopConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      if [ -L "$HOME/.config/btop" ]; then
        BTOP_TARGET=$(readlink "$HOME/.config/btop")
        $DRY_RUN_CMD rm "$HOME/.config/btop"
        $DRY_RUN_CMD mkdir -p "$HOME/.config/btop"
        $DRY_RUN_CMD cp -r "$BTOP_TARGET/"* "$HOME/.config/btop/"
        $DRY_RUN_CMD chmod -R u+w "$HOME/.config/btop"
      fi
    '';
  };
}
