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

  cc-metrics = pkgs.writeShellScriptBin "cc-metrics" ''
    exec ${pkgs.deno}/bin/deno run --allow-read --allow-write="''${CLAUDE_CONFIG_DIR:-''${HOME}/.config/claude},''${HOME}/.claude,''${HOME}/.config/claude" --allow-env=HOME,CLAUDE_CONFIG_DIR "''${HOME}/.config/claude/scripts/cc-metrics.ts" "$@"
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
    ./catppuccin-palette.nix
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

  catppuccin = {
    enable = true;
    flavor = "mocha";
    accent = "blue";
    # 既存 symlink と競合するため後の Phase で有効化
    delta.enable = false;
    # 手動管理 or カスタムテンプレートで管理
    nvim.enable = false;
    ghostty.enable = false;
    helix.enable = false;
    wezterm.enable = false;
    yazi.enable = false;
  };

  programs = {
    home-manager.enable = true;

    btop = {
      enable = true;
      settings = {
        # color_theme は catppuccin/nix で管理
        theme_background = false;
        truecolor = true;
        force_tty = false;
        presets = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default cpu:0:block,net:0:tty";
        vim_keys = false;
        rounded_corners = true;
        graph_symbol = "braille";
        graph_symbol_cpu = "default";
        graph_symbol_mem = "default";
        graph_symbol_net = "default";
        graph_symbol_proc = "default";
        shown_boxes = "cpu mem net proc";
        update_ms = 2000;
        proc_sorting = "cpu lazy";
        proc_reversed = false;
        proc_tree = false;
        proc_colors = true;
        proc_gradient = true;
        proc_per_core = false;
        proc_mem_bytes = true;
        proc_cpu_graphs = true;
        proc_info_smaps = false;
        proc_left = false;
        proc_filter_kernel = false;
        proc_aggregate = false;
        cpu_graph_upper = "Auto";
        cpu_graph_lower = "Auto";
        cpu_invert_lower = true;
        cpu_single_graph = false;
        cpu_bottom = false;
        show_uptime = true;
        show_cpu_watts = true;
        check_temp = true;
        cpu_sensor = "Auto";
        show_coretemp = true;
        cpu_core_map = "";
        temp_scale = "celsius";
        base_10_sizes = false;
        show_cpu_freq = true;
        clock_format = "%X";
        background_update = true;
        custom_cpu_name = "";
        disks_filter = "";
        mem_graphs = true;
        mem_below_net = false;
        zfs_arc_cached = true;
        show_swap = true;
        swap_disk = true;
        show_disks = true;
        only_physical = true;
        use_fstab = true;
        zfs_hide_datasets = false;
        disk_free_priv = false;
        show_io_stat = true;
        io_mode = false;
        io_graph_combined = false;
        io_graph_speeds = "";
        net_download = 100;
        net_upload = 100;
        net_auto = true;
        net_sync = true;
        net_iface = "";
        base_10_bitrate = "Auto";
        show_battery = true;
        selected_battery = "Auto";
        show_battery_watts = true;
        log_level = "WARNING";
      };
    };

    lazygit = {
      enable = true;
      settings = {
        gui = {
          showRandomTip = false;
          showBottomLine = false;
          showCommandLog = false;
          scrollHeight = 10;
          scrollPastBottom = true;
          sidePanelWidth = 0.3333;
          expandFocusedSidePanel = true;
          mainPanelSplitMode = "flexible";
          showIcons = true;
          nerdFontsVersion = "3";
          # theme は catppuccin/nix で管理
        };
        git = {
          autoFetch = true;
          autoRefresh = true;
          branchLogCmd = "git log --graph --color=always --abbrev-commit --decorate --date=relative --pretty=medium {{branchName}} --";
          pagers = [
            {pager = "delta --dark --paging=never";}
          ];
        };
        os = {
          editPreset = "nvim-remote";
        };
        notARepository = "skip";
        promptToReturnFromSubprocess = false;
        customCommands = [
          {
            key = "R";
            context = "commits";
            command = "git rebase -i {{.SelectedLocalCommit.Hash}}~1";
            description = "Interactive rebase from this commit";
            output = "terminal";
          }
          {
            key = "F";
            context = "files";
            command = "git commit --fixup={{.SelectedLocalCommit.Hash}}";
            description = "Create fixup commit for selected commit";
            loadingText = "Creating fixup commit...";
          }
          {
            key = "S";
            context = "commits";
            command = "git rebase -i --autosquash {{.SelectedLocalCommit.Hash}}~1";
            description = "Autosquash fixup commits";
            output = "terminal";
          }
          {
            key = "O";
            context = "localBranches";
            command = "gh pr checkout {{.SelectedLocalBranch.Name}}";
            description = "Checkout GitHub PR";
            loadingText = "Checking out PR...";
          }
          {
            key = "V";
            context = "localBranches";
            command = "gh pr view --web {{.SelectedLocalBranch.Name}}";
            description = "View PR in browser";
          }
          {
            key = "Y";
            context = "localBranches";
            command = "echo -n {{.SelectedLocalBranch.Name}} | clip.exe";
            description = "Copy branch name to clipboard";
          }
          {
            key = "Y";
            context = "commits";
            command = "echo -n {{.SelectedLocalCommit.Hash}} | clip.exe";
            description = "Copy commit hash to clipboard";
          }
          {
            key = "P";
            context = "localBranches";
            command = "git push --force-with-lease origin {{.SelectedLocalBranch.Name}}";
            description = "Force push with lease";
            loadingText = "Force pushing...";
          }
          {
            key = "f";
            context = "remotes";
            command = "git fetch --prune {{.SelectedRemote.Name}}";
            description = "Fetch and prune remote";
            loadingText = "Fetching...";
          }
        ];
        keybinding = {
          universal = {
            "scrollUpMain-alt1" = "K";
            "scrollDownMain-alt1" = "J";
          };
          commits = {
            moveDownCommit = "<c-j>";
            moveUpCommit = "<c-k>";
          };
        };
      };
    };
  }; # programs

  home = {
    inherit username;
    homeDirectory = homeDir;
    stateVersion = "24.11";

    # 以下のパッケージは programs.* モジュールで管理:
    # bat, btop, delta, eza, fzf, gh, git, lazygit, zoxide
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
        # https://github.com/sinelaw/fresh
        fresh-editor # ターミナルテキストエディタ (LSP対応)
        # https://github.com/cmatsuoka/figlet
        figlet # ASCIIアート
        # https://github.com/b4b4r07/gomi
        gomi # ゴミ箱CLI (rm alternative)
        # https://github.com/ChrisBuilds/terminaltexteffects
        terminaltexteffects # ターミナルテキストエフェクト (tte)
        # https://gitlab.com/graphviz/graphviz
        graphviz # グラフ可視化
        # https://github.com/casey/just
        just # コマンドランナー
        # https://github.com/jqlang/jq
        jq # JSON プロセッサ
        # https://github.com/johnkerl/miller
        miller # CSV/JSON処理
        # https://github.com/jesseduffield/lazydocker
        lazydocker # Docker TUI
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
        # https://github.com/xampprocky/tokei
        tokei # コード統計ツール (行数カウント)
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
        # https://exiftool.org/
        exiftool # 画像/動画メタデータ編集
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

        # https://github.com/openai/codex
        codex # OpenAI Codex CLI
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
        # https://github.com/lunarmodules/luacheck
        luaPackages.luacheck # Lua linter (.luacheckrc 用)
        # https://github.com/nrslib/takt
        takt # AI Agent オーケストレーション (overlay)
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
        # https://github.com/microsoft/typescript-go
        typescript-go # TypeScript Go コンパイラ (tsgo)
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
        biome # Web ツールチェーン (formatter + linter)
        # https://github.com/conventional-changelog/commitlint
        commitlint # コミットメッセージ lint
        # https://github.com/evilmartians/lefthook
        lefthook # Git hooks マネージャ
        # https://github.com/secretlint/secretlint
        secretlint # シークレット検出 (overlay)

        #--- CLI ツール (overlay) ---#
        cc-statusline # 高速 Claude Code statusline (Zig)
        daily # 日記メモツール (Zig)

        #--- ユーザースクリプト ラッパー ---#
        mmd # Mermaid図レンダラー (bin/mermaid-render.ts)
        cc-metrics # スキル・インストラクション統合メトリクス表示

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

        # https://github.com/Feel-ix-343/markdown-oxide
        markdown-oxide # Markdown PKM LSP (Obsidian互換、バックリンク/デイリーノート)

        # https://github.com/atusy/kakehashi
        kakehashi # Tree-sitter Language Server (overlay)

        #--- Go 製パッケージ ---#
        # https://github.com/k1LoW/deck
        deck-slides # Markdown → Google Slides

        #--- Rust 製パッケージ ---#
        # https://github.com/mlange-42/git-graph
        git-graph # Git コミットグラフ可視化 (fork: kokatsu/git-graph)
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
        # https://valgrind.org
        valgrind # メモリデバッグ・プロファイリング
        # https://sourceware.org/gdb/
        gdb # デバッガ・カバレッジ計測 (cc-statusline)
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
        CODEX_HOME = "${config.xdg.configHome}/codex";
        TERMFRAME_CONFIG = "${config.xdg.configHome}/termframe/config.toml";
        CATPPUCCIN_VIVID_THEME = "catppuccin-${config.catppuccin.flavor}";
        CC_STATUSLINE_THEME = "catppuccin-${config.catppuccin.flavor}";
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
        ".config/claude/settings.json".source = ../../.config/claude/settings.json;
        ".config/claude/CLAUDE.md".source = ../../.config/claude/.CLAUDE.md;
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
        ".config/claude/hooks/run-deno-hook.sh" = {
          source = ../../.config/claude/hooks/run-deno-hook.sh;
          executable = true;
        };
        ".config/claude/hooks/skill-tracker.ts" = {
          source = ../../.config/claude/hooks/skill-tracker.ts;
          executable = true;
        };
        ".config/claude/hooks/instructions-tracker.ts" = {
          source = ../../.config/claude/hooks/instructions-tracker.ts;
          executable = true;
        };
        ".config/claude/hooks/banned-commands.json".source = ../../.config/claude/hooks/banned-commands.json;
        ".config/claude/hooks/check-banned-commands.sh" = {
          source = ../../.config/claude/hooks/check-banned-commands.sh;
          executable = true;
        };
        ".config/claude/hooks/check-managed-paths.sh" = {
          source = ../../.config/claude/hooks/check-managed-paths.sh;
          executable = true;
        };
        ".config/claude/scripts/cc-metrics.ts" = {
          source = ../../.config/claude/scripts/cc-metrics.ts;
          executable = true;
        };
        # Claude Code キーバインド (CLAUDE_CONFIG_DIR で ~/.config/claude を使用)
        ".config/claude/keybindings.json".source = ../../.config/claude/keybindings.json;

        # takt (XDG未対応のため ~/.takt/ にシンボリンク)
        ".takt/config.yaml".source = ../../.config/takt/config.yaml;
        ".takt/pieces".source = ../../.config/takt/pieces;
        ".config/delta".source = ../../.config/delta;
        ".config/fastfetch".source = ../../.config/fastfetch;
        ".config/fresh/config.json".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        in
          builtins.toJSON {
            version = 1;
            theme = names.kebab;
            check_for_updates = false;
          };

        ".config/fresh/themes/${(config.catppuccinLib.flavorNames config.catppuccin.flavor).kebab}.json".text = let
          p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
          rgb = c: [c.rgb.r c.rgb.g c.rgb.b];
        in
          builtins.toJSON {
            name = names.kebab;
            editor = {
              bg = rgb p.base;
              fg = rgb p.text;
              cursor = rgb p.rosewater;
              selection_bg = rgb p.surface1;
              current_line_bg = rgb p.surface0;
              line_number_fg = rgb p.surface1;
              line_number_bg = rgb p.base;
              whitespace_indicator_fg = rgb p.surface1;
            };
            ui = {
              tab_active_fg = rgb p.mauve;
              tab_active_bg = rgb p.base;
              tab_inactive_fg = rgb p.subtext0;
              tab_inactive_bg = rgb p.mantle;
              tab_separator_bg = rgb p.crust;
              tab_hover_bg = rgb p.surface0;
              status_bar_fg = rgb p.subtext1;
              status_bar_bg = rgb p.mantle;
              prompt_fg = rgb p.base;
              prompt_bg = rgb p.rosewater;
              prompt_selection_fg = rgb p.text;
              prompt_selection_bg = rgb p.surface1;
              popup_border_fg = rgb p.blue;
              popup_bg = rgb p.surface0;
              popup_selection_bg = rgb p.surface1;
              popup_text_fg = rgb p.text;
              suggestion_bg = rgb p.surface0;
              suggestion_selected_bg = rgb p.surface1;
              menu_bg = rgb p.surface0;
              menu_fg = rgb p.overlay2;
              menu_active_bg = rgb p.surface1;
              menu_active_fg = rgb p.text;
              menu_dropdown_bg = rgb p.surface0;
              menu_dropdown_fg = rgb p.text;
              menu_highlight_bg = rgb p.mauve;
              menu_highlight_fg = rgb p.base;
              menu_border_fg = rgb p.blue;
              menu_separator_fg = rgb p.surface1;
              menu_hover_bg = rgb p.surface1;
              menu_hover_fg = rgb p.text;
              menu_disabled_fg = rgb p.overlay0;
              menu_disabled_bg = rgb p.surface0;
              help_bg = rgb p.surface0;
              help_fg = rgb p.overlay2;
              help_key_fg = rgb p.sky;
              help_separator_fg = rgb p.surface1;
              help_indicator_fg = rgb p.red;
              help_indicator_bg = rgb p.surface0;
              split_separator_fg = rgb p.crust;
              scrollbar_track_fg = rgb p.surface1;
              scrollbar_thumb_fg = rgb p.overlay0;
              scrollbar_track_hover_fg = rgb p.surface2;
              scrollbar_thumb_hover_fg = rgb p.blue;
              settings_selected_bg = rgb p.surface1;
              settings_selected_fg = rgb p.text;
            };
            search = {
              match_bg = rgb p.yellow;
              match_fg = rgb p.base;
            };
            diagnostic = {
              error_fg = rgb p.red;
              error_bg = rgb p.base;
              warning_fg = rgb p.yellow;
              warning_bg = rgb p.base;
              info_fg = rgb p.sky;
              info_bg = rgb p.base;
              hint_fg = rgb p.teal;
              hint_bg = rgb p.base;
            };
            syntax = {
              keyword = rgb p.mauve;
              string = rgb p.green;
              comment = rgb p.overlay2;
              function = rgb p.blue;
              type = rgb p.yellow;
              variable = rgb p.text;
              constant = rgb p.peach;
              operator = rgb p.sky;
            };
          };
        ".config/git-graph/models/catppuccin-${config.catppuccin.flavor}.toml".text = let
          p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        in ''
          # ${names.spaced} Theme for git-graph

          persistence = [
            "^(master|main|trunk)$",
            "^(develop|dev)$",
            "^release.*$",
            "^hotfix.*$",
            "^bugfix.*$",
            "^feature.*$",
          ]

          order = ["^(master|main|trunk)$", "^(hotfix|release).*$", "^(develop|dev)$"]

          [terminal_colors]
          matches = [
            ["^(master|main|trunk)$", ["bright_blue"]],
            ["^(develop|dev)$", ["bright_yellow"]],
            ["^(feature|fork/).*$", ["bright_magenta", "bright_cyan"]],
            ["^release.*$", ["bright_green"]],
            ["^(bugfix|hotfix).*$", ["bright_red"]],
            ["^tags/.*$", ["cyan"]],
          ]
          unknown = ["yellow", "magenta", "bright_cyan", "cyan"]

          [svg_colors]
          matches = [
            ["^(master|main|trunk)$", ["${p.blue.hex}"]],
            ["^(develop|dev)$", ["${p.yellow.hex}"]],
            ["^(feature|fork/).*$", ["${p.mauve.hex}", "${p.lavender.hex}"]],
            ["^release.*$", ["${p.green.hex}"]],
            ["^(bugfix|hotfix).*$", ["${p.red.hex}"]],
            ["^tags/.*$", ["${p.teal.hex}"]],
          ]
          unknown = ["${p.peach.hex}", "${p.pink.hex}", "${p.sapphire.hex}", "${p.sky.hex}"]
        '';
        ".config/gomi/config.yaml".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
          p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
        in ''
          core:
            trash:
              strategy: auto
              home_fallback: true
              forbidden_paths:
                - /
                - /etc
                - /usr
                - /bin
                - /sbin
                - /var
                - /boot
                - /proc
                - /sys
            restore:
              confirm: false
              verbose: true
            permanent_delete:
              enable: true

          ui:
            density: spacious
            preview:
              syntax_highlight: true
              colorscheme: ${names.kebab}
              directory_command: ls -F -A --color=always
            style:
              list_view:
                cursor: "${p.mauve.hex}"
                selected: "${p.green.hex}"
                filter_match: "${p.peach.hex}"
                filter_prompt: "${p.blue.hex}"
                indent_on_select: false
            exit_message: "bye!"
            paginator_type: dots

          history:
            include:
              within_days: 100
            exclude:
              files:
                - .DS_Store
              patterns:
                - ^go\..*
              globs:
                - "*.jpg"
              size:
                min: 0KB
                max: 10GB

          logging:
            enabled: false
        '';
        ".config/moxide".source = ../../.config/moxide;
        ".config/ov".source = ../../.config/ov;
        ".config/pg".source = ../../.config/pg;
        ".config/.ripgreprc".source = ../../.config/.ripgreprc;

        # WezTerm: 個別ファイルをリンク
        ".config/wezterm/background.lua".text = let
          p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
          staticContent = builtins.readFile ../../.config/wezterm/background.static.lua;
        in
          builtins.replaceStrings
          ["__CATPPUCCIN_BASE__" "__BASE_OPACITY__"]
          [
            p.base.hex
            (
              if isDarwin
              then "0.85"
              else "1.0"
            )
          ]
          staticContent;
        ".config/wezterm/colors.lua".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
          p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
        in ''
          local M = {}

          local color_scheme = '${names.spaced}'

          local palette = {
            rosewater = '${p.rosewater.hex}',
            flamingo = '${p.flamingo.hex}',
            pink = '${p.pink.hex}',
            mauve = '${p.mauve.hex}',
            red = '${p.red.hex}',
            maroon = '${p.maroon.hex}',
            peach = '${p.peach.hex}',
            yellow = '${p.yellow.hex}',
            green = '${p.green.hex}',
            teal = '${p.teal.hex}',
            sky = '${p.sky.hex}',
            sapphire = '${p.sapphire.hex}',
            blue = '${p.blue.hex}',
            lavender = '${p.lavender.hex}',
            text = '${p.text.hex}',
            subtext1 = '${p.subtext1.hex}',
            subtext0 = '${p.subtext0.hex}',
            overlay2 = '${p.overlay2.hex}',
            overlay1 = '${p.overlay1.hex}',
            overlay0 = '${p.overlay0.hex}',
            surface2 = '${p.surface2.hex}',
            surface1 = '${p.surface1.hex}',
            surface0 = '${p.surface0.hex}',
            base = '${p.base.hex}',
            mantle = '${p.mantle.hex}',
            crust = '${p.crust.hex}',
          }

          M.palette = palette

          M.apply_to_config = function(config)
            config.color_scheme = color_scheme
            config.colors = {
              cursor_bg = palette.sapphire,
              cursor_fg = palette.base,
              cursor_border = palette.sapphire,
              compose_cursor = palette.peach,
              split = palette.blue,
            }
            config.command_palette_bg_color = palette.surface0
            config.command_palette_fg_color = palette.text
          end

          return M
        '';
        ".config/wezterm/format.lua".source = ../../.config/wezterm/format.lua;
        ".config/wezterm/keybinds.lua".source = ../../.config/wezterm/keybinds.lua;
        ".config/wezterm/mac.lua".source = ../../.config/wezterm/mac.lua;
        ".config/wezterm/platform.lua".source = ../../.config/wezterm/platform.lua;
        ".config/wezterm/stylua.toml".source = ../../.config/wezterm/stylua.toml;
        ".config/wezterm/wezterm.lua".source = ../../.config/wezterm/wezterm.lua;
        ".config/wezterm/windows.lua".source = ../../.config/wezterm/windows.lua;

        # 新規追加
        # Ghostty: 個別ファイルをリンク
        ".config/ghostty/config".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
          staticConfig = builtins.readFile ../../.config/ghostty/config.static;
        in
          "# テーマ (catppuccin/nix パレットモジュール管理)\ntheme = ${names.kebab}\n" + staticConfig;
        ".config/ghostty/themes/catppuccin-mocha".source = ../../.config/ghostty/themes/catppuccin-mocha;

        # yazi: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
        # これにより ya pkg コマンドで package.toml への書き込みが可能
        ".config/yazi" = {
          source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/yazi";
          force = true;
        };
        ".config/octorus/config.toml".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        in ''
          editor = "nvim"

          [diff]
          theme = "${names.spaced}"
          tab_width = 4

          [keybindings]
          approve = "a"
          request_changes = "r"
          comment = "c"
          suggestion = "s"

          [ai]
          reviewer = "claude"
          reviewee = "claude"
          max_iterations = 10
          timeout_secs = 600
        '';
        ".config/helix/config.toml".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
          staticConfig = builtins.readFile ../../.config/helix/config.static.toml;
        in
          ''
            [theme]
            dark = "${names.snake}_transparent"
            light = "catppuccin_latte"
            fallback = "${names.snake}_transparent"

          ''
          + staticConfig;

        ".config/helix/languages.toml".source = ../../.config/helix/languages.toml;

        ".config/helix/themes/${(config.catppuccinLib.flavorNames config.catppuccin.flavor).snake}_transparent.toml".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        in ''
          inherits = "${names.snake}"
          "ui.background" = {}

          "ui.statusline.normal" = { fg = "base", bg = "blue", modifiers = ["bold"] }
          "ui.statusline.insert" = { fg = "base", bg = "green", modifiers = ["bold"] }
          "ui.statusline.select" = { fg = "base", bg = "mauve", modifiers = ["bold"] }

          "ui.bufferline" = { fg = "subtext0", bg = "mantle" }
          "ui.bufferline.active" = { fg = "crust", bg = "mauve", modifiers = ["bold"] }
          "ui.bufferline.background" = { bg = "crust" }

          "ui.virtual.inlay-hint" = { fg = "sapphire", bg = "surface1" }
          "ui.virtual.inlay-hint.parameter" = { fg = "lavender", bg = "surface1" }
          "ui.virtual.inlay-hint.type" = { fg = "flamingo", bg = "surface1" }

          "ui.cursor.primary.normal" = { bg = "blue" }

          "ui.cursorline.primary" = { bg = "#343f5a" }

          "diagnostic.error" = { underline = { color = "red", style = "line" } }
          "diagnostic.warning" = { underline = { color = "yellow", style = "line" } }
          "diagnostic.info" = { underline = { color = "sky", style = "line" } }
          "diagnostic.hint" = { underline = { color = "teal", style = "line" } }
          "diagnostic.unnecessary" = { modifiers = ["dim"] }
        '';
        ".config/biome".source = ../../.config/biome;
        ".config/lazydocker".source = ../../.config/lazydocker;
        ".config/readline".source = ../../.config/readline;
        ".config/taplo".source = ../../.config/taplo;
        ".config/termframe".source = ../../.config/termframe;
        # tmux is managed by programs.tmux (nix/home/programs/tmux.nix)
        ".config/treemd/config.toml".text = let
          names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        in ''
          [ui]
          theme = "${names.pascal}"
          outline_width = 30

          [terminal]
          color_mode = "auto"

          [image]
          renderer = "kitty"
        '';

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
        # lazygit WSL 固有設定 (クリップボード連携)
        ".config/lazygit/config.wsl.yml".source = ../../.config/lazygit/config.wsl.yml;
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

  # Home Manager 適用後に実行されるスクリプト
  home.activation = {
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

    # codex: git管理の設定 (tui等) とローカルの [projects] をマージ
    mergeCodexConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      CODEX_DIR="$HOME/.config/codex"
      BASE="${dotfilesDir}/.config/codex/config.toml"
      TARGET="$CODEX_DIR/config.toml"
      $DRY_RUN_CMD mkdir -p "$CODEX_DIR"
      if [ -f "$TARGET" ]; then
        # 既存の [projects] セクションを抽出
        PROJECTS=$(${pkgs.gnused}/bin/sed -n '/^\[projects[."\[]/,$ p' "$TARGET")
        $DRY_RUN_CMD cp "$BASE" "$TARGET"
        if [ -n "$PROJECTS" ]; then
          printf '\n%s\n' "$PROJECTS" >> "$TARGET"
        fi
      else
        $DRY_RUN_CMD cp "$BASE" "$TARGET"
      fi
    '';

    # WezTerm: WSL → Windows 側に設定ファイルをコピー (home-manager switch で自動反映)
    copyWezTermConfig = lib.mkIf (!isDarwin) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WINUSER=$(/mnt/c/Windows/System32/cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
      WEZTERM_DIR="/mnt/c/Users/$WINUSER/.config/wezterm"
      if [ -d "/mnt/c/Users/$WINUSER" ]; then
        $DRY_RUN_CMD mkdir -p "$WEZTERM_DIR"
        for f in "$HOME/.config/wezterm/"*.lua; do
          [ -f "$f" ] && $DRY_RUN_CMD cp -f "$f" "$WEZTERM_DIR/"
        done
      fi
    '');

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
