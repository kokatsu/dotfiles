{
  pkgs,
  lib,
  config,
  validDotfilesDir,
  isWSL,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  flavor = config.catppuccin.flavor;
  p = config.catppuccinLib.palettes.${flavor};
  names = config.catppuccinLib.flavorNames flavor;
in {
  # .config へのシンボリックリンク
  home.file =
    {
      # nvim: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
      # これによりlazy-lock.jsonへの書き込みがリポジトリに反映される
      ".config/nvim" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/nvim";
        force = true;
      };
      # fff.nvim: Nix ビルド版 (Rust バックエンド同梱) を lazy.nvim の dir 参照用に配置
      ".local/share/nvim/nix-plugins/fff.nvim".source = pkgs.vimPlugins.fff-nvim;
      ".config/delta".source = ../../.config/delta;
      ".config/fastfetch/config.jsonc".text = let
        rgb = c: "${toString c.rgb.r};${toString c.rgb.g};${toString c.rgb.b}";
        staticContent = builtins.readFile ../../.config/fastfetch/config.static.jsonc;
      in
        builtins.replaceStrings
        [
          "__RED_RGB__"
          "__BLUE_RGB__"
          "__YELLOW_RGB__"
          "__MAUVE_RGB__"
          "__GREEN_RGB__"
          "__PINK_RGB__"
          "__SKY_RGB__"
          "__PEACH_RGB__"
          "__LAVENDER_RGB__"
          "__TEAL_RGB__"
        ]
        [
          (rgb p.red)
          (rgb p.blue)
          (rgb p.yellow)
          (rgb p.mauve)
          (rgb p.green)
          (rgb p.pink)
          (rgb p.sky)
          (rgb p.peach)
          (rgb p.lavender)
          (rgb p.teal)
        ]
        staticContent;
      ".config/git-graph/models/catppuccin-${flavor}.toml".text = ''
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
      ".config/gomi/config.yaml".text = ''
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

      # Ghostty: catppuccin/nix 管理 (ビルトインテーマを利用)
      ".config/ghostty/config".text = let
        staticConfig = builtins.readFile ../../.config/ghostty/config.static;
      in
        "# テーマ (catppuccin.flavor から導出、ビルトインテーマを利用)\ntheme = ${names.kebab}\n" + staticConfig;

      # yazi: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
      # これにより ya pkg コマンドで package.toml への書き込みが可能
      ".config/yazi" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/yazi";
        force = true;
      };
      # herdr is managed by nix/home/programs/herdr.nix
      ".config/octorus/config.toml".text = let
        staticContent = builtins.readFile ../../.config/octorus/config.static.toml;
      in
        builtins.replaceStrings ["__CATPPUCCIN_THEME__"] [names.spaced] staticContent;
      ".config/octorus/themes/${names.spaced}.tmTheme".source =
        ../../.config/bat/themes + "/${names.spaced}.tmTheme";
      ".config/bulletty/feeds.opml".source = ../../.config/bulletty/feeds.opml;
      ".config/bulletty/feeds-forum.opml".source = ../../.config/bulletty/feeds-forum.opml;
      ".config/biome".source = ../../.config/biome;
      ".config/lazydocker/config.yml".text = let
        staticContent = builtins.readFile ../../.config/lazydocker/config.static.yml;
      in
        builtins.replaceStrings
        [
          "__ACTIVE_BORDER__"
          "__INACTIVE_BORDER__"
          "__SELECTED_BG__"
          "__OPTIONS_TEXT__"
        ]
        [
          p.blue.hex
          p.overlay0.hex
          p.surface0.hex
          p.blue.hex
        ]
        staticContent;
      ".config/taplo".source = ../../.config/taplo;
      # tmux is managed by programs.tmux (nix/home/programs/tmux.nix)
      # bin: ユーザースクリプト (Deno/Bun/Shell)
      # mkOutOfStoreSymlink で直接リンクし、スクリプト編集がリポジトリに反映される
      ".local/bin/scripts" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/bin";
        force = true;
      };
      # treemd: ビルトイン UI テーマは CatppuccinMocha のみ。
      # 他フレーバー対応のため [theme] で全色を上書きする。
      # コードブロックは bat と同じ tmTheme を流用。
      ".config/treemd/config.toml".text = let
        rgb = c: "{ rgb = [${toString c.rgb.r}, ${toString c.rgb.g}, ${toString c.rgb.b}] }";
      in ''
        [ui]
        theme = "CatppuccinMocha"
        code_theme = "${names.spaced}"
        outline_width = 30

        [terminal]
        color_mode = "auto"

        [image]
        renderer = "kitty"

        [theme]
        background = ${rgb p.base}
        foreground = ${rgb p.text}
        heading_1 = ${rgb p.mauve}
        heading_2 = ${rgb p.pink}
        heading_3 = ${rgb p.blue}
        heading_4 = ${rgb p.teal}
        heading_5 = ${rgb p.green}
        border_focused = ${rgb p.lavender}
        border_unfocused = ${rgb p.surface2}
        selection_bg = ${rgb p.surface1}
        selection_fg = ${rgb p.text}
        status_bar_bg = ${rgb p.mauve}
        status_bar_fg = ${rgb p.base}
        inline_code_fg = ${rgb p.peach}
        inline_code_bg = ${rgb p.surface0}
        code_fence = ${rgb p.overlay0}
        bold_fg = ${rgb p.text}
        italic_fg = ${rgb p.subtext1}
        list_bullet = ${rgb p.sapphire}
        blockquote_border = ${rgb p.mauve}
        blockquote_fg = ${rgb p.subtext0}
        search_match_bg = ${rgb p.yellow}
        search_match_fg = ${rgb p.base}
        search_current_bg = ${rgb p.peach}
        search_current_fg = ${rgb p.base}
      '';
      ".config/treemd/code-themes/${names.spaced}.tmTheme".source =
        ../../.config/bat/themes + "/${names.spaced}.tmTheme";
    }
    # Docker CLI plugins (macOSではOrbStackが管理)
    // lib.optionalAttrs (!isDarwin) {
      ".docker/cli-plugins/docker-buildx".source = "${pkgs.docker-buildx}/bin/docker-buildx";
      ".docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/bin/docker-compose";
    }
    // lib.optionalAttrs isWSL {
      # lazygit WSL 固有設定 (クリップボード連携)
      ".config/lazygit/config.wsl.yml".source = ../../.config/lazygit/config.wsl.yml;
    }
    # macOS: Biome グローバル設定 (~/Library/Application Support/biome/)
    // lib.optionalAttrs isDarwin {
      "Library/Application Support/biome/.biome.jsonc".source = ../../.config/biome/.biome.jsonc;
    };
}
