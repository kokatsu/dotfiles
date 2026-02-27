{
  pkgs,
  lib,
  config,
  inputs,
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

  # ユーザースクリプトのラッパー (bin/ 内の Deno/Bun スクリプトを短い名前で実行)
  mmd = pkgs.writeShellScriptBin "mmd" ''
    exec ${pkgs.deno}/bin/deno run --allow-read --allow-write "''${DOTFILES_DIR:-${dotfilesDir}}/bin/mermaid-render.ts" "$@"
  '';

  # WSL: Claude Code は clip.exe をハードコードで使用するが UTF-8 を正しく扱えない
  # xsel (X11) + win32yank (Windows/Win+V履歴) の両方に書き込む
  clip-exe-wrapper = pkgs.writeShellScriptBin "clip.exe" ''
    input=$(cat)
    printf '%s' "$input" | ${pkgs.xsel}/bin/xsel --clipboard --input
    printf '%s' "$input" | win32yank.exe -i
  '';

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
    ./programs/gh.nix
    ./programs/git.nix
    ./programs/karabiner.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    ./programs/zoxide.nix
    ./programs/zsh.nix
  ];

  home = {
    inherit username;
    homeDirectory = homeDir;
    stateVersion = "24.11";

    # 以下のパッケージは programs.* モジュールで管理:
    # bat, delta, eza, fzf, gh, git, zoxide (nix/home/programs/)
    packages = with pkgs;
      [
        # https://github.com/anthropics/agent-browser
        agent-browser # ブラウザ自動化エージェント (overlay)

        #####################################
        # ランタイム (グローバルデフォルト)
        #####################################
        # https://github.com/golang/go
        go
        # https://github.com/nodejs/node
        nodejs_24
        # https://github.com/pnpm/pnpm
        pnpm # 高速 Node.js パッケージマネージャ
        # https://github.com/python/cpython
        (python3.withPackages (ps:
          with ps; [
            # https://github.com/optuna/optuna
            optuna # ハイパーパラメータ最適化フレームワーク
          ]))
        # https://github.com/ruby/ruby
        stablePkgs.ruby_3_1 # nixpkgs-stable (24.05) から取得
        # https://github.com/rust-lang/rustup
        rustup # Rust ツールチェーンマネージャ

        #--- Playwright (ブラウザ自動化) ---#
        # https://github.com/microsoft/playwright
        playwright-cli # coding agents 用 CLI (overlay)
        playwright-driver # Nix 管理のブラウザバイナリ

        #####################################
        # CLIツール
        #####################################
        # https://gitlab.freedesktop.org/fontconfig/fontconfig
        fontconfig # フォント管理 (fc-list等)
        # https://github.com/ip7z/7zip
        _7zz # 7-Zip アーカイバ
        # https://github.com/charmbracelet/glow
        glow # Markdownプレビュー
        # https://github.com/jdx/mise
        mise # タスクランナー + プロジェクトごとのツールバージョン管理
        # https://github.com/rclone/rclone
        rclone # クラウドストレージ同期
        # https://github.com/github/copilot-cli
        github-copilot-cli # GitHub Copilot CLI
        # https://github.com/aristocratos/btop
        btop # リソースモニター
        # https://github.com/hpjansson/chafa
        chafa # 画像→テキスト
        # https://github.com/curl/curl
        curl # データ転送ツール
        # https://github.com/duckdb/duckdb
        duckdb # OLAP DB
        # https://github.com/bootandy/dust
        dust # ディスク使用量可視化 (du alternative)
        # https://github.com/fastfetch-cli/fastfetch
        fastfetch # システム情報表示
        # https://github.com/sharkdp/fd
        fd # ファイル検索 (find alternative)
        # https://github.com/cmatsuoka/figlet
        figlet # ASCIIアート
        # https://github.com/b4b4r07/gomi
        gomi # ゴミ箱CLI (rm alternative)
        # https://github.com/ChrisBuilds/terminaltexteffects
        terminaltexteffects # ターミナルテキストエフェクト (tte)
        # https://gitlab.com/graphviz/graphviz
        graphviz # グラフ可視化
        # https://github.com/jqlang/jq
        jq # JSON プロセッサ
        # https://github.com/johnkerl/miller
        miller # CSV/JSON処理
        # https://github.com/jesseduffield/lazydocker
        lazydocker # Docker TUI
        # https://github.com/jesseduffield/lazygit
        lazygit # Git TUI
        # https://github.com/xwmx/nb
        nb # ノート管理
        # https://github.com/nmap/nmap
        nmap # ネットワークスキャナ
        # https://github.com/noborus/ov
        ov # ページャー
        # https://github.com/BurntSushi/ripgrep
        ripgrep # 高速テキスト検索 (grep alternative)
        # https://github.com/boyter/scc
        scc # コード統計
        # https://github.com/homeport/termshot
        termshot # ターミナルスクリーンショット (PNG)
        # https://github.com/jonas/tig
        tig # Git TUI
        # https://github.com/Epistates/treemd
        treemd # Markdown navigator TUI
        # https://github.com/Gaurav-Gosain/tuios
        tuios # ターミナルベースウィンドウマネージャ
        # https://github.com/tree-sitter/tree-sitter
        tree-sitter # Treesitter CLI (nvim-treesitter パーサービルド用)
        # https://github.com/sharkdp/vivid
        vivid # LS_COLORS ジェネレーター
        # https://www.gnu.org/software/wget/
        wget # ファイルダウンローダー
        # https://github.com/bgreenwell/xleak
        xleak # Excel TUI viewer
        # https://github.com/sxyazi/yazi
        yazi # ファイルマネージャ TUI
        # https://github.com/zimfw/zimfw
        zimfw # Zsh framework

        #####################################
        # メディア/画像処理
        #####################################
        # https://github.com/nicholasHuang/bento4
        bento4 # MP4 解析/操作ツールキット (mp4dump, mp4info 等)
        # https://github.com/dirkvdb/ffmpegthumbnailer
        ffmpegthumbnailer # 動画サムネイル (yazi プレビュー用)
        # https://github.com/karlstav/cava
        cava # 音声ビジュアライザ
        # https://github.com/dominikwilkowski/cfonts
        cfonts # ASCIIアート
        # https://github.com/ImageMagick/ImageMagick
        imagemagick # 画像処理ツールキット
        # https://github.com/eddieantonio/imgcat
        imgcat # 画像表示
        # https://github.com/cslarsen/jp2a
        jp2a # JPG→ASCII変換
        # https://github.com/cacalabs/libcaca
        libcaca # テキストグラフィックス
        # https://potrace.sourceforge.net/
        potrace # ビットマップ→ベクター変換
        # https://github.com/tesseract-ocr/tesseract
        tesseract # OCR
        # https://github.com/jstkdng/ueberzugpp
        ueberzugpp # 画像表示 (Sixel/Kitty/X11)
        # https://github.com/libvips/libvips
        vips # 画像処理ライブラリ

        #--- ドキュメント ---#
        # https://ghostscript.com/
        ghostscript # PostScript/PDF インタプリタ
        # https://github.com/jgm/pandoc
        pandoc # ドキュメント変換ツール
        # https://poppler.freedesktop.org/
        poppler-utils # PDF操作ツール (pdftotext, pdfimages等)

        #--- その他言語/ツール ---#
        # https://github.com/luarocks/luarocks
        luarocks # Luaパッケージマネージャ
        # https://github.com/ziglang/zig
        zig # Zig プログラミング言語

        #####################################
        # 開発ツール
        #####################################
        # https://github.com/oven-sh/bun
        bun # JavaScript ランタイム + バンドラー
        # https://github.com/anthropics/claude-code
        claude-code # AI コーディングエージェント (overlay)
        inputs.claude-chill.packages.${system}.default # PTY proxy for Claude Code
        # https://github.com/openai/codex
        codex # OpenAI Codex CLI
        # https://github.com/google-gemini/gemini-cli
        gemini-cli # Google Gemini CLI
        # https://github.com/gitleaks/gitleaks
        gitleaks # シークレット検出
        # https://github.com/denoland/deno
        deno # JavaScript/TypeScript ランタイム
        # https://github.com/pypa/pipx
        pipx # Python CLI管理
        # https://github.com/kamadorueda/alejandra
        alejandra # Nix formatter
        # https://github.com/nerdypepper/statix
        statix # Nix linter
        # https://github.com/astro/deadnix
        deadnix # Nix dead code finder
        # https://github.com/JohnnyMorganz/StyLua
        stylua # Lua formatter
        # https://github.com/Kampfkarren/selene
        selene # Lua linter
        # https://github.com/textlint/textlint
        textlint # 日本語校正 (overlay)
        # https://github.com/crate-ci/typos
        typos # タイポ検出
        # https://github.com/koalaman/shellcheck
        shellcheck # シェルスクリプト linter
        # https://github.com/mvdan/sh
        shfmt # シェルスクリプト formatter
        # https://github.com/editorconfig-checker/editorconfig-checker
        editorconfig-checker # EditorConfig 準拠チェッカー
        # https://github.com/igorshubovych/markdownlint-cli
        markdownlint-cli # Markdown linter
        # https://github.com/google/yamlfmt
        yamlfmt # YAML formatter

        #--- プレゼン ---#
        # https://github.com/marp-team/marp-cli
        marp-cli # Markdown → スライド
        # https://github.com/mfontanini/presenterm
        presenterm # ターミナルプレゼンテーション

        #--- Spotify ---#
        # https://github.com/aome510/spotify-player
        spotify-player # Spotify TUI クライアント

        #####################################
        # Language Servers
        #####################################
        # https://github.com/bash-lsp/bash-language-server
        bash-language-server # Bash/Sh LSP (ShellCheck + shfmt 統合)
        # https://github.com/withastro/language-tools
        astro-language-server # Astro LSP
        # https://github.com/github/copilot-language-server-release
        copilot-language-server # GitHub Copilot LSP
        # https://github.com/rcjsuen/dockerfile-language-server-nodejs
        dockerfile-language-server # Dockerfile LSP
        # https://github.com/LuaLS/lua-language-server
        lua-language-server # Lua LSP
        # https://github.com/oxalica/nil
        nil # Nix LSP
        # https://github.com/nix-community/nixd
        nixd # Nix LSP (補完強化)
        # https://github.com/sveltejs/language-tools
        svelte-language-server # Svelte LSP
        # https://github.com/tailwindlabs/tailwindcss-intellisense
        tailwindcss-language-server # Tailwind CSS LSP
        # https://github.com/tamasfe/taplo
        taplo # TOML LSP
        # https://github.com/hrsh7th/vscode-langservers-extracted
        vscode-langservers-extracted # HTML/CSS/JSON/ESLint LSP
        # https://github.com/yioneko/vtsls
        vtsls # TypeScript LSP
        # https://github.com/vuejs/language-tools
        vue-language-server # Vue LSP (overlay でピン留め)
        # https://github.com/redhat-developer/yaml-language-server
        yaml-language-server # YAML LSP

        #####################################
        # Git hooks/lint ツール
        #####################################
        # https://github.com/biomejs/biome
        biome # Web ツールチェーン (formatter + linter, overlay)
        # https://github.com/conventional-changelog/commitlint
        commitlint # コミットメッセージ lint
        # https://github.com/evilmartians/lefthook
        lefthook # Git hooks マネージャ
        # https://github.com/secretlint/secretlint
        secretlint # シークレット検出 (overlay)

        #--- CLI ツール (overlay) ---#
        cc-statusline # 高速 Claude Code statusline (Zig)
        # https://github.com/ryoppippi/ccusage
        ccusage # Claude API使用量表示

        #--- ユーザースクリプト ラッパー ---#
        mmd # Mermaid図レンダラー (bin/mermaid-render.ts)

        #--- Language Servers (overlay) ---#
        # https://github.com/antonk52/cssmodules-language-server
        cssmodules-language-server # CSS Modules LSP
        # https://github.com/xna00/unocss-language-server
        unocss-language-server # UnoCSS LSP

        #--- X API v2 シミュレーター (overlay) ---#
        # https://github.com/xdevplatform/playground
        x-api-playground # X API v2 ローカルサーバー
      ]
      ++ lib.optionals (!isCI) [
        # CI ではスキップ (ビルド時間短縮)

        #--- D言語ツール ---#
        # https://github.com/ldc-developers/ldc
        ldc # D言語コンパイラ (LLVM ベース)
        # https://github.com/dlang/dub
        dub # D言語パッケージマネージャ
        # https://github.com/dlang-community/dfmt
        dformat # D言語 formatter
        # https://github.com/dlang/tools
        dtools # D言語ツール (rdmd, dustmite 等)

        # https://github.com/artempyanykh/marksman
        marksman # Markdown LSP (overlay: GitHub バイナリ、.NET ビルド問題回避)

        # Tree-sitter Language Server (埋め込み言語対応)
        # doCheck = false: Nixサンドボックス内でgitが利用できずテストが失敗するため
        (inputs.kakehashi.packages.${system}.default.overrideAttrs (_: {doCheck = false;}))

        #--- Go 製パッケージ ---#
        # https://github.com/k1LoW/deck
        deck-slides # Markdown → Google Slides

        #--- Rust 製パッケージ ---#
        # https://github.com/mlange-42/git-graph
        git-graph # Git コミットグラフ可視化 (fork: kokatsu/git-graph)
        # https://github.com/trasta298/keifu
        keifu # Git コミットグラフ TUI (overlay)
        # https://github.com/ushironoko/octorus
        octorus # GitHub PR レビュー TUI (overlay)
        # https://github.com/pamburus/termframe
        termframe # ターミナルスクリーンショット (SVG, Nerd Font対応, overlay)

        #--- エディタ nightly (ソースビルド) ---#
        # https://github.com/helix-editor/helix
        helix
        # https://github.com/neovim/neovim
        neovim

        #--- フォント (Nerd Fonts) ---#
        # https://github.com/ryanoasis/nerd-fonts
        nerd-fonts.fira-code
        nerd-fonts.hack
        nerd-fonts.symbols-only
        # https://github.com/yuru7/HackGen
        hackgen-nf-font # HackGen + Nerd Fonts (日本語対応)
      ]
      ++ lib.optionals isDarwin [
        # macOS専用
        # https://github.com/julienXX/terminal-notifier
        terminal-notifier # macOS通知
      ]
      ++ lib.optionals (!isDarwin) [
        # Linux/WSL専用
        clip-exe-wrapper # Claude Code WSL文字化け対策 (clip.exe → xsel)
        # https://github.com/docker/buildx
        docker-buildx # Docker BuildKit
        # https://github.com/docker/compose
        docker-compose # macOSではOrbStackを使用
        google-chrome # Chromium ベースブラウザ
        # https://github.com/googlefonts/noto-cjk
        noto-fonts-cjk-sans # 日本語フォント
      ]
      ++ lib.optionals (isDarwin && !isCI) [
        # macOS専用 (CI ではスキップ)

        # ターミナル (WezTerm nightly)
        # Ghostty は Homebrew cask で管理 (nix/darwin/default.nix)
        # WSLではWindows側にインストールするためLinuxでは除外
        # https://github.com/wez/wezterm (fork: kokatsu/wezterm, unfocused split pane 対応)
        inputs.wezterm.packages.${system}.default
      ];

    # PATH に追加 (ユーザースクリプト)
    sessionPath = [
      "${config.home.homeDirectory}/.local/bin/scripts"
      "${config.home.homeDirectory}/.gem/bin" # ruby-lsp 等の gem 実行ファイル
    ];

    sessionVariables =
      {
        EDITOR = "nvim";
        VISUAL = "nvim";
        GEM_HOME = "${config.home.homeDirectory}/.gem"; # gem インストール先 (バージョン非依存)
        XDG_CONFIG_HOME = "${config.home.homeDirectory}/.config";
        ZDOTDIR = "${config.xdg.configHome}/zsh";
        BAT_CONFIG_DIR = "${config.xdg.configHome}/bat";
        CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
        PSQLRC = "${config.xdg.configHome}/pg/.psqlrc";
        RIPGREP_CONFIG_PATH = "${config.xdg.configHome}/.ripgreprc";
        INPUTRC = "${config.xdg.configHome}/readline/inputrc";
        TERMFRAME_CONFIG = "${config.xdg.configHome}/termframe/config.toml";
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

    # .config へのシンボリックリンク
    file =
      {
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
        ".config/claude/CLAUDE.md".source = ../../.config/claude/CLAUDE.md;
        ".config/claude/skills".source = ../../.config/claude/skills;
        ".config/claude/rules".source = ../../.config/claude/rules;
        ".config/claude/file-suggestion.sh" = {
          source = ../../.config/claude/file-suggestion.sh;
          executable = true;
        };
        ".config/claude/hooks/session-logger.ts" = {
          source = ../../.config/claude/hooks/session-logger.ts;
          executable = true;
        };
        ".config/claude/hooks/pre-compact-handover.ts" = {
          source = ../../.config/claude/hooks/pre-compact-handover.ts;
          executable = true;
        };
        # Claude Code キーバインド (CLAUDE_CONFIG_DIR で ~/.config/claude を使用)
        ".config/claude/keybindings.json".source = ../../.config/claude/keybindings.json;
        ".config/claude-chill.toml".source = ../../.config/claude-chill.toml;
        # Gemini CLI (XDG未対応のため ~/.gemini/ にシンボリンク)
        ".gemini/settings.json".source = ../../.config/gemini/settings.json;
        ".config/delta".source = ../../.config/delta;
        ".config/fastfetch".source = ../../.config/fastfetch;
        ".config/git-graph".source = ../../.config/git-graph;
        ".config/gomi".source = ../../.config/gomi;
        ".config/keifu".source = ../../.config/keifu;
        ".config/ov".source = ../../.config/ov;
        ".config/pg".source = ../../.config/pg;
        ".config/.ripgreprc".source = ../../.config/.ripgreprc;

        # WezTerm: 個別ファイルをリンク
        ".config/wezterm/background.lua".source = ../../.config/wezterm/background.lua;
        ".config/wezterm/colors.lua".source = ../../.config/wezterm/colors.lua;
        ".config/wezterm/format.lua".source = ../../.config/wezterm/format.lua;
        ".config/wezterm/keybinds.lua".source = ../../.config/wezterm/keybinds.lua;
        ".config/wezterm/mac.lua".source = ../../.config/wezterm/mac.lua;
        ".config/wezterm/platform.lua".source = ../../.config/wezterm/platform.lua;
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
        ".config/octorus".source = ../../.config/octorus;
        ".config/helix".source = ../../.config/helix;
        ".config/biome".source = ../../.config/biome;
        ".config/lazydocker".source = ../../.config/lazydocker;
        ".config/lazygit".source = ../../.config/lazygit;
        ".config/readline".source = ../../.config/readline;
        ".config/taplo".source = ../../.config/taplo;
        ".config/termframe".source = ../../.config/termframe;
        # tmux is managed by programs.tmux (nix/home/programs/tmux.nix)
        ".config/treemd".source = ../../.config/treemd; # XDG_CONFIG_HOME で解決

        # bin: ユーザースクリプト (Deno/Bun/Shell)
        # mkOutOfStoreSymlink で直接リンクし、スクリプト編集がリポジトリに反映される
        ".local/bin/scripts" = {
          source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/bin";
          force = true;
        };
      }
      # Docker CLI plugins (macOSではOrbStackが管理)
      // lib.optionalAttrs (!isDarwin) {
        ".docker/cli-plugins/docker-buildx".source = "${pkgs.docker-buildx}/bin/docker-buildx";
        ".docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/bin/docker-compose";
      }
      # macOS: Biome グローバル設定 (~/Library/Application Support/biome/)
      // lib.optionalAttrs isDarwin {
        "Library/Application Support/biome/.biome.jsonc".source = ../../.config/biome/.biome.jsonc;
      };
  };

  xdg.enable = true;

  # 不要なNixストアを自動削除 (週1回、7日以上前のものを削除)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

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
    # win32yank.exe を ~/bin/ にコピー (WSL クリップボード連携)
    copyWin32yank = lib.mkIf (!isDarwin) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p "$HOME/bin"
      $DRY_RUN_CMD cp -f "${pkgs.win32yank}/bin/win32yank.exe" "$HOME/bin/win32yank.exe"
      $DRY_RUN_CMD chmod +x "$HOME/bin/win32yank.exe"
    '');
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

    # zsh config.d / functions.d をコピー (git管理外ファイル用)
    setupZshExtraFiles = lib.hm.dag.entryAfter ["linkGeneration"] ''
      for subdir in config.d functions.d; do
        SOURCE="${dotfilesDir}/.config/zsh/$subdir"
        TARGET="$HOME/.config/zsh/$subdir"
        if [ -d "$SOURCE" ]; then
          $DRY_RUN_CMD mkdir -p "$TARGET"
          for f in "$SOURCE"/*.zsh; do
            [ -f "$f" ] && $DRY_RUN_CMD cp "$f" "$TARGET/" 2>/dev/null || true
          done
        fi
      done
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

    # WezTerm.app を /Applications にリンク (Dock対応)
    linkWezTermApp = lib.mkIf (isDarwin && !isCI) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WEZTERM_APP="${inputs.wezterm.packages.${system}.default}/Applications/WezTerm.app"
      if [ -d "$WEZTERM_APP" ]; then
        $DRY_RUN_CMD rm -f /Applications/WezTerm.app
        $DRY_RUN_CMD ln -sf "$WEZTERM_APP" /Applications/WezTerm.app
      fi
    '');
  };
}
