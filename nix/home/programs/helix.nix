{
  config,
  inputs,
  lib,
  pkgs,
  validDotfilesDir,
  ...
}: let
  # gitignore 対象のため flake のソースに入らず、作業ツリーから直接リンクする
  ignoreFile = "${validDotfilesDir}/.config/helix/ignore";
  names = config.catppuccinLib.flavorNames config.catppuccin.flavor;

  webCodeActions = ["source.addMissingImports.ts" "source.fixAll.eslint"];
  webLanguageServers = [
    "vtsls"
    "vscode-eslint-language-server"
    "biome-lsp-proxy"
    "cssmodules"
    "tailwindcss-ls"
    "unocss"
  ];
in {
  home.file.".config/helix/ignore" = lib.mkIf (builtins.pathExists ignoreFile) {
    source = config.lib.file.mkOutOfStoreSymlink ignoreFile;
  };

  programs.helix = {
    enable = true;
    # overlay や nixpkgs の差し替えを通すと helix.cachix.org の store path と
    # 一致せず Rust のフルビルドになる (flake.nix の helix input 参照)。
    package = inputs.helix.packages.${pkgs.stdenv.hostPlatform.system}.default;

    # ビルトインの catppuccin_<flavor> は各 UI に bg を塗るため、
    # bg を外して WezTerm の背景透過を通す (Neovim の transparent_background 相当)。
    # inherits の上書きは scope 単位で丸ごと置き換わるので、残す fg なども書き直す。
    themes."${names.snake}_transparent" = {
      inherits = names.snake;
      "ui.background" = {};
      "ui.statusline" = {fg = "subtext1";};
      "ui.statusline.inactive" = {fg = "surface2";};
      "ui.bufferline.background" = {};
      "ui.bufferline" = {fg = "subtext0";};
      "ui.bufferline.active" = {
        fg = "mauve";
        underline = {
          color = "mauve";
          style = "line";
        };
      };
      "ui.popup" = {fg = "text";};
      "ui.menu" = {fg = "overlay2";};
      "ui.help" = {fg = "overlay2";};
    };

    settings = {
      theme = "${names.snake}_transparent";

      editor = {
        line-number = "relative";
        cursorline = true;
        color-modes = true;
        bufferline = "multiple";
        rulers = [80 100];
        text-width = 80;
        end-of-line-diagnostics = "hint";
        # Neovim の scrolloff / sidescrolloff = 8 に合わせる (helix の既定は 5)
        scrolloff = 8;
        # clipboard-provider は指定しない。helix の自動検出が WSL では x-sel を選び、
        # WSLg 経由で Windows のクリップボードと同期する。win32-yank を明示すると
        # yank/paste の度に Windows プロセスの起動 (実測 462ms) を待つことになる。

        # Neovim では insert モードを抜けるたびに保存している (keymaps/editor.lua)。
        # helix に同じフックは無いため、無操作タイマーとフォーカス喪失で代替する。
        auto-save = {
          focus-lost = true;
          after-delay.enable = true;
        };

        # space b を開いた時点で直前のバッファを選択しておき、2 ファイル間の往復を
        # Enter だけで済ませる (既定は current)。
        buffer-picker.start-position = "previous";

        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };

        file-picker.hidden = false;

        # popup / menu の bg を透過させたので、本文との境界を枠線で示す
        popup-border = "all";

        # code-action-hint は既定の layout に含まれないため明示する。
        # 他の要素は helix の既定値と同じ。
        gutters.layout = ["diagnostics" "code-action-hint" "spacer" "line-numbers" "spacer" "diff"];

        indent-guides = {
          render = true;
          character = "▏";
        };

        inline-diagnostics.cursor-line = "warning";

        lsp = {
          display-inlay-hints = true;
          display-progress-messages = true;
          # カーソル下のシンボルの参照を自動ハイライトする (Neovim の snacks.words 相当)。
          auto-document-highlight = true;
        };

        soft-wrap = {
          enable = true;
          wrap-indicator = "↪ ";
        };

        statusline = {
          left = [
            "mode"
            "spinner"
            "version-control"
            "file-name"
            "read-only-indicator"
            "file-modification-indicator"
          ];
          right = [
            "diagnostics"
            "workspace-diagnostics"
            "selections"
            "position"
            "position-percentage"
            "file-type"
          ];
        };
      };

      # Neovim (autocmds.lua) と同じく y だけをシステムクリップボードへ同期し、
      # d / c ではクリップボードを上書きしない。
      keys = let
        yankBoth = ["yank" "yank_to_clipboard"];

        # yazi をファイルピッカーにする (ピッカーのキーは再割り当てできず、階層移動に h/l を使えないため)。
        # 手順は https://yazi-rs.github.io/docs/tips#helix のまま。yazi が抜けた
        # alternate screen と bracketed paste を printf で戻してから再描画する。
        yaziFrom = entry: let
          chooser = "/tmp/unique-ca1ea106";
        in [
          ":sh rm -f ${chooser}"
          '':insert-output yazi "${entry}" --chooser-file=${chooser}''
          '':sh printf "\x1b[?1049h\x1b[?2004h" > /dev/tty''
          ":open %sh{cat ${chooser}}"
          ":redraw"
          ":set mouse false"
          ":set mouse true"
        ];
      in {
        normal = {
          y = yankBoth;
          # workspace_directory は開いているファイルではなく hx を起動したディレクトリから辿る
          C-y = yaziFrom "%{workspace_directory}";
          C-e = yaziFrom "%{buffer_name}";
        };
        select.y = yankBoth;
      };
    };

    # Neovim (.config/nvim/after/lsp/) と同じ language server 構成に寄せる。
    # helix の既定 (languages.toml) で定義済みのサーバーは name を参照するだけでよく、
    # 未定義のものだけここで language-server に足している。
    #
    # 既定との主な差分:
    #   - TypeScript 系は typescript-language-server ではなく vtsls (PATH にあるのは vtsls だけ)
    #   - nix は nil を外して nixd のみ、toml は tombi を外して taplo のみ
    #   - tailwindcss / unocss / cssmodules を Web 系の言語に追加
    languages = {
      language-server = {
        cssmodules.command = "cssmodules-language-server";

        unocss = {
          command = "unocss-language-server";
          args = ["--stdio"];
        };

        # biome / eslint はプロジェクトに設定ファイルがあるときだけ起動させる
        # (Neovim 側は root_markers / root_dir で同じ制御をしている)。
        biome-lsp-proxy.required-root-patterns = ["biome.json" "biome.jsonc" ".biome.json" ".biome.jsonc"];
        vscode-eslint-language-server.required-root-patterns = [".eslintrc*" "eslint.config.*"];

        # nixd の設定は after/lsp/nixd.lua から移植。flake の nixpkgs と
        # home-manager のオプションを補完候補に出すための expr。
        nixd.config.nixd = {
          nixpkgs.expr = ''import (builtins.getFlake ("git+file://" + toString ./.)).inputs.nixpkgs {}'';
          options.home-manager.expr = ''(let sudoUser = builtins.getEnv "SUDO_USER"; username = builtins.getEnv "USER"; user = if sudoUser != "" then sudoUser else if username == "" || username == "root" then "user" else username; in (builtins.getFlake ("git+file://" + toString ./.)).homeConfigurations.''${user}.options)'';
          formatting.command = ["alejandra"];
        };
      };

      # code-actions-on-save は保存時に LSP の code action を順に実行する。
      # 提供していないサーバーがいる場合はその action だけスキップされるので、
      # ESLint が無いプロジェクトでも source.fixAll.eslint は無害。
      language =
        map (name: {
          inherit name;
          code-actions-on-save = webCodeActions;
          language-servers = webLanguageServers;
        }) ["typescript" "tsx" "javascript" "jsx"]
        ++ [
          {
            name = "svelte";
            language-servers = [
              "svelteserver"
              "vscode-eslint-language-server"
              "biome-lsp-proxy"
              "tailwindcss-ls"
              "unocss"
            ];
          }
          {
            name = "css";
            language-servers = ["vscode-css-language-server" "tailwindcss-ls" "unocss"];
          }
          {
            name = "scss";
            language-servers = ["vscode-css-language-server" "tailwindcss-ls" "unocss"];
          }
          {
            name = "html";
            language-servers = ["vscode-html-language-server" "tailwindcss-ls" "unocss"];
          }
          {
            name = "json";
            language-servers = ["vscode-json-language-server" "biome-lsp-proxy"];
          }
          {
            name = "jsonc";
            language-servers = ["vscode-json-language-server" "biome-lsp-proxy"];
          }
          # 既定は nil と nixd の両方が起動する。Neovim は nixd のみ。
          {
            name = "nix";
            language-servers = ["nixd"];
          }
          # 既定は taplo と tombi。tombi は入れていないので taplo だけにする。
          {
            name = "toml";
            language-servers = ["taplo"];
          }
          # 既定は marksman が先頭だが、入れているのは markdown-oxide のみ。
          {
            name = "markdown";
            language-servers = ["markdown-oxide"];
          }
        ];
    };
  };
}
