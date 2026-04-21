{
  pkgs,
  lib,
  inputs,
  stablePkgs,
  dotfilesDir ? "",
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.stdenv.hostPlatform) system;

  # ユーザースクリプトのラッパー (bin/ 内の Deno/Bun スクリプトを短い名前で実行)
  cc-metrics = pkgs.writeShellScriptBin "cc-metrics" ''
    exec ${pkgs.deno}/bin/deno run --allow-read --allow-write="''${CLAUDE_CONFIG_DIR:-''${HOME}/.config/claude},''${HOME}/.claude,''${HOME}/.config/claude" --allow-env=HOME,CLAUDE_CONFIG_DIR "''${HOME}/.config/claude/scripts/cc-metrics.ts" "$@"
  '';

  feed-watch = pkgs.writeShellScriptBin "feed-watch" ''
    exec "''${DOTFILES_DIR:-${dotfilesDir}}/bin/feed-watch" "$@"
  '';

  feed-summarize = pkgs.writeShellScriptBin "feed-summarize" ''
    exec "''${DOTFILES_DIR:-${dotfilesDir}}/bin/feed-summarize" "$@"
  '';

  # WSL: Claude Code は clip.exe をハードコードで使用するが UTF-8 を正しく扱えない
  # xsel (X11) + win32yank (Windows/Win+V履歴) の両方に書き込む
  clip-exe-wrapper = pkgs.writeShellScriptBin "clip.exe" ''
    input=$(cat)
    printf '%s' "$input" | ${pkgs.xsel}/bin/xsel --clipboard --input
    printf '%s' "$input" | win32yank.exe -i
  '';
in {
  # 以下のパッケージは programs.* モジュールで管理:
  # bat, btop, delta, eza, fzf, gh, git, lazygit, zoxide
  home.packages = with pkgs;
    [
      # https://github.com/vercel-labs/agent-browser
      agent-browser # ブラウザ自動化エージェント

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
      # nixpkgs-unstable の ibis-framework 12.0.0 がビルド失敗するため stable から取得
      # (optuna → plotly → narwhals → ibis-framework の依存チェーン)
      (stablePkgs.python3.withPackages (ps:
        with ps; [
          # https://github.com/optuna/optuna
          optuna # ハイパーパラメータ最適化フレームワーク
        ]))
      # https://github.com/ruby/ruby
      stablePkgs.ruby_3_2 # nixpkgs-stable から取得 (理由は flake.nix 参照)
      # https://github.com/rust-lang/rustup
      rustup # Rust ツールチェーンマネージャ

      #--- Playwright (ブラウザ自動化) ---#
      # https://github.com/microsoft/playwright
      playwright-driver # Nix 管理のブラウザバイナリ (agent-browser 用)

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
      # https://github.com/crocidb/bulletty
      bulletty # TUI RSS/Atom フィードリーダー
      # https://github.com/carapace-sh/carapace-bin
      carapace # マルチシェル補完エンジン (carapace-bin)
      # https://github.com/hpjansson/chafa
      chafa # 画像→テキスト
      # https://github.com/curl/curl
      curl # データ転送ツール
      # https://github.com/eradman/entr
      entr # ファイル変更監視 → コマンド実行
      # https://github.com/inotify-tools/inotify-tools (Linux)
      # https://man.openbsd.org/kqueue (macOS)
      keychain # SSH/GPG エージェント管理
      # https://github.com/duckdb/duckdb
      duckdb # OLAP DB
      # https://github.com/Wilfred/difftastic
      difftastic # 構文を理解する構造的 diff (tree-sitter ベース, difft)
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
      # https://github.com/mikefarah/yq
      yq-go # YAML/JSON/XML プロセッサ (yq コマンド)
      # https://github.com/johnkerl/miller
      miller # CSV/JSON処理
      # https://github.com/jesseduffield/lazydocker
      lazydocker # Docker TUI
      # https://github.com/xwmx/nb
      nb # ノート管理
      # https://github.com/rofl0r/ncdu
      ncdu # ディスク使用量 TUI (du alternative)
      # https://github.com/nurse/nkf
      nkf # 文字コード変換
      # https://github.com/nmap/nmap
      nmap # ネットワークスキャナ
      # https://github.com/noborus/ov
      ov # ページャー
      # https://github.com/BurntSushi/ripgrep
      ripgrep # 高速テキスト検索 (grep alternative)
      # https://github.com/boyter/scc
      scc # コード統計
      # http://www.dest-unreach.org/socat/
      socat # 多機能ソケットリレー
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
      # https://gitlab.com/OldManProgrammer/unix-tree
      tree # ディレクトリツリー表示
      # https://github.com/tree-sitter/tree-sitter
      tree-sitter # Treesitter CLI (nvim-treesitter パーサービルド用)
      # https://github.com/soimort/translate-shell
      translate-shell # 多言語翻訳 CLI (trans)
      # https://github.com/sharkdp/vivid
      vivid # LS_COLORS ジェネレーター
      # https://infozip.sourceforge.net/UnZip.html
      unzip # ZIP アーカイブ展開
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
      # https://github.com/FFmpeg/FFmpeg
      ffmpeg # メディア処理ツールキット
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
      # https://github.com/textlint/textlint
      (pkgs.symlinkJoin {
        name = "textlint-with-rules";
        paths = [
          pkgs.textlint
          pkgs.textlint-rule-preset-ja-technical-writing
          pkgs.textlint-rule-terminology
        ];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/textlint \
            --set NODE_PATH "$out/lib/node_modules"
        '';
      }) # 日本語校正 (nixpkgs)
      # https://github.com/Redocly/redocly-cli
      redocly # OpenAPI プレビュー / lint
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
      # https://github.com/apple/pkl
      pkl # Pkl CLI (configuration as code language)
      # https://github.com/apple/pkl-lsp
      pkl-lsp # Pkl LSP
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
      # https://github.com/ziglang/zls
      zls # Zig Language Server
      # https://github.com/tekumara/typos-lsp
      typos-lsp # タイポ検出 LSP

      #####################################
      # Git hooks/lint ツール
      #####################################
      # https://github.com/biomejs/biome
      biome # Web ツールチェーン (formatter + linter)
      # https://github.com/conventional-changelog/commitlint
      commitlint # コミットメッセージ lint
      # https://github.com/evilmartians/lefthook
      lefthook # Git hooks マネージャ

      #--- AWS ---#
      # https://github.com/aws/aws-cli
      awscli2 # AWS CLI v2
      # https://github.com/aws/session-manager-plugin
      ssm-session-manager-plugin # AWS SSM セッションマネージャ

      #--- CLI ツール (overlay) ---#
      cc-statusline # 高速 Claude Code statusline (Zig)
      cc-filter # Claude Code Bash 出力圧縮フィルタ (Zig)
      daily # 日記メモツール (Zig)
      memo # タイムスタンプ付き単独メモツール (Zig)

      #--- ユーザースクリプト ラッパー ---#
      feed-watch # GitHub フィード監視 (bin/feed-watch)
      feed-summarize # GitHub コミット要約 (bin/feed-summarize)

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

      # https://github.com/denoland/deno
      deno # JavaScript/TypeScript ランタイム (trybuild tests fail on aarch64-darwin)
      cc-metrics # スキル・インストラクション統合メトリクス表示 — depends on deno

      #--- D言語ツール ---#
      # https://github.com/ldc-developers/ldc
      ldc # D言語コンパイラ (LLVM ベース)
      # https://github.com/dlang/dub
      dub # D言語パッケージマネージャ
      # https://github.com/dlang-community/dfmt
      dformat # D言語 formatter
      # https://github.com/dlang/tools
      dtools # D言語ツール (rdmd, dustmite 等)
      # https://github.com/Pure-D/serve-d
      serve-d # D言語 LSP サーバー
      # https://github.com/dlang-community/DCD
      dcd # D 補完デーモン (serve-d の補完/定義ジャンプバックエンド)

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
      # https://github.com/brevity1swos/rgx
      rgx-cli # ターミナル正規表現テスター (regex101 の TUI 版, overlay)
      # https://github.com/pamburus/termframe
      termframe # ターミナルスクリーンショット (SVG, Nerd Font対応, overlay)

      #--- エディタ ---#
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
      # https://github.com/HakonHarnes/img-clip.nvim
      pngpaste # Neovim画像貼り付け (img-clip.nvim依存)
      # https://github.com/julienXX/terminal-notifier
      terminal-notifier # macOS通知
    ]
    ++ lib.optionals (!isDarwin) [
      # Linux/WSL専用
      # https://github.com/containers/bubblewrap
      bubblewrap # サンドボックスツール (Codex CLI 用)
      # https://github.com/inotify-tools/inotify-tools
      inotify-tools # ファイルシステムイベント監視
      # https://github.com/strace/strace
      strace # システムコールトレーサ
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
}
