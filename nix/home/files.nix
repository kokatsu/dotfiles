{
  pkgs,
  lib,
  config,
  dotfilesDir ? "",
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  validDotfilesDir =
    if isCI
    then "/tmp/dotfiles"
    else if dotfilesDir == ""
    then throw "dotfilesDir is empty. Did you forget --impure flag?"
    else dotfilesDir;
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
      ".config/claude/settings.json".source = ../../.config/claude/settings.json;
      ".config/claude/CLAUDE.md".source = ../../.config/claude/.CLAUDE.md;
      ".config/claude/skills".source = ../../.config/claude/skills;
      ".config/claude/commands".source = ../../.config/claude/commands;
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
      ".config/claude/hooks/gh-api-guard.sh" = {
        source = ../../.config/claude/hooks/gh-api-guard.sh;
        executable = true;
      };
      ".config/claude/scripts/cc-metrics.ts" = {
        source = ../../.config/claude/scripts/cc-metrics.ts;
        executable = true;
      };
      # Claude Code キーバインド (CLAUDE_CONFIG_DIR で ~/.config/claude を使用)
      ".config/claude/keybindings.json".source = ../../.config/claude/keybindings.json;

      # Claude Code カスタムテーマ (2.1.118+): 4 flavor を ~/.config/claude/themes/ に生成
      # 実体は `home.file` ブロック末尾で `// (builtins.listToAttrs ...)` として合流
      # 起動中もファイルウォッチで反映。`/theme` で "Catppuccin <Flavor>" を選択

      ".config/cmux/settings.json".source = ../../.config/cmux/settings.json;
      ".config/delta".source = ../../.config/delta;
      ".config/fastfetch/config.jsonc".text = let
        p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
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

      # Ghostty: catppuccin/nix 管理 (ビルトインテーマを利用)
      ".config/ghostty/config".text = let
        names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        staticConfig = builtins.readFile ../../.config/ghostty/config.static;
      in
        "# テーマ (catppuccin.flavor から導出、ビルトインテーマを利用)\ntheme = ${names.kebab}\n" + staticConfig;

      # yazi: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
      # これにより ya pkg コマンドで package.toml への書き込みが可能
      ".config/yazi" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/yazi";
        force = true;
      };
      ".config/octorus/config.toml".text = let
        names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        staticContent = builtins.readFile ../../.config/octorus/config.static.toml;
      in
        builtins.replaceStrings ["__CATPPUCCIN_THEME__"] [names.spaced] staticContent;
      ".config/octorus/themes/${(config.catppuccinLib.flavorNames config.catppuccin.flavor).spaced}.tmTheme".source =
        ../../.config/bat/themes + "/${(config.catppuccinLib.flavorNames config.catppuccin.flavor).spaced}.tmTheme";
      ".config/bulletty/feeds.opml".source = ../../.config/bulletty/feeds.opml;
      ".config/bulletty/feeds-forum.opml".source = ../../.config/bulletty/feeds-forum.opml;
      ".config/biome".source = ../../.config/biome;
      ".config/lazydocker/config.yml".text = let
        p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
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
      ".config/termframe".source = ../../.config/termframe;
      # tmux is managed by programs.tmux (nix/home/programs/tmux.nix)
      # bin: ユーザースクリプト (Deno/Bun/Shell)
      # mkOutOfStoreSymlink で直接リンクし、スクリプト編集がリポジトリに反映される
      ".local/bin/scripts" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/bin";
        force = true;
      };
    }
    # treemd: ビルトイン UI テーマは CatppuccinMocha のみ。
    # 他フレーバー対応のため [theme] で全色を上書きする。
    # コードブロックは bat と同じ tmTheme を流用。
    // (let
      names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
      p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
      rgb = c: "{ rgb = [${toString c.rgb.r}, ${toString c.rgb.g}, ${toString c.rgb.b}] }";
    in {
      ".config/treemd/config.toml".text = ''
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
    })
    # Claude Code カスタムテーマ: 4 flavor (latte/frappe/macchiato/mocha) を生成
    // (let
      mkClaudeTheme = flavor: let
        p = config.catppuccinLib.palettes.${flavor};
        names = config.catppuccinLib.flavorNames flavor;
        themeBase =
          if flavor == "latte"
          then "light"
          else "dark";
        # ratio は 0-100 (foreground の比率)
        # Claude Code は `rgb(r,g,b)` / `#rrggbb` / `ansi256(n)` / `ansi:<name>` を受理する
        # 注: 2.1.118 時点で diffAdded/diffRemoved(Dimmed) の背景色は override されず
        #     base defaults が使われるバグがある。ここの値は将来修正された時用
        blend = fg: bg: ratio: let
          mix = a: b: (a * ratio + b * (100 - ratio)) / 100;
        in "rgb(${toString (mix fg.rgb.r bg.rgb.r)},${toString (mix fg.rgb.g bg.rgb.g)},${toString (mix fg.rgb.b bg.rgb.b)})";
      in
        builtins.toJSON {
          name = names.spaced;
          base = themeBase;
          overrides = {
            diffAdded = blend p.green p.base 18;
            diffRemoved = blend p.red p.base 18;
            diffAddedDimmed = blend p.green p.base 10;
            diffRemovedDimmed = blend p.red p.base 10;

            text = p.text.hex;
            inverseText = p.base.hex;
            inactive = p.overlay1.hex;
            inactiveShimmer = p.overlay2.hex;
            subtle = p.surface1.hex;

            claude = p.peach.hex;
            claudeShimmer = p.flamingo.hex;
            claudeBlue_FOR_SYSTEM_SPINNER = p.lavender.hex;
            claudeBlueShimmer_FOR_SYSTEM_SPINNER = p.sky.hex;

            autoAccept = p.mauve.hex;
            permission = p.lavender.hex;
            permissionShimmer = p.sky.hex;
            suggestion = p.lavender.hex;
            remember = p.lavender.hex;
            merged = p.mauve.hex;

            bashBorder = p.pink.hex;
            promptBorder = p.overlay0.hex;
            promptBorderShimmer = p.overlay1.hex;

            planMode = p.teal.hex;
            ide = p.sapphire.hex;
            fastMode = p.peach.hex;
            fastModeShimmer = p.flamingo.hex;

            success = p.green.hex;
            error = p.red.hex;
            warning = p.yellow.hex;
            warningShimmer = p.yellow.hex;

            diffAddedWord = p.green.hex;
            diffRemovedWord = p.maroon.hex;

            userMessageBackground = p.surface0.hex;
            userMessageBackgroundHover = p.surface1.hex;
            messageActionsBackground = p.mantle.hex;
            selectionBg = p.surface1.hex;
            bashMessageBackgroundColor = p.surface0.hex;
            memoryBackgroundColor = p.surface0.hex;

            red_FOR_SUBAGENTS_ONLY = p.red.hex;
            blue_FOR_SUBAGENTS_ONLY = p.blue.hex;
            green_FOR_SUBAGENTS_ONLY = p.green.hex;
            yellow_FOR_SUBAGENTS_ONLY = p.yellow.hex;
            purple_FOR_SUBAGENTS_ONLY = p.mauve.hex;
            orange_FOR_SUBAGENTS_ONLY = p.peach.hex;
            pink_FOR_SUBAGENTS_ONLY = p.pink.hex;
            cyan_FOR_SUBAGENTS_ONLY = p.sky.hex;

            briefLabelYou = p.sapphire.hex;
            briefLabelClaude = p.peach.hex;

            rate_limit_fill = p.lavender.hex;
            rate_limit_empty = p.surface1.hex;

            rainbow_red = p.red.hex;
            rainbow_orange = p.peach.hex;
            rainbow_yellow = p.yellow.hex;
            rainbow_green = p.green.hex;
            rainbow_blue = p.blue.hex;
            rainbow_indigo = p.lavender.hex;
            rainbow_violet = p.mauve.hex;

            rainbow_red_shimmer = p.maroon.hex;
            rainbow_orange_shimmer = p.flamingo.hex;
            rainbow_yellow_shimmer = p.yellow.hex;
            rainbow_green_shimmer = p.teal.hex;
            rainbow_blue_shimmer = p.sapphire.hex;
            rainbow_indigo_shimmer = p.lavender.hex;
            rainbow_violet_shimmer = p.pink.hex;
          };
        };
    in
      builtins.listToAttrs (map (flavor: {
        name = ".config/claude/themes/catppuccin-${flavor}.json";
        value = {text = mkClaudeTheme flavor;};
      }) ["latte" "frappe" "macchiato" "mocha"]))
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
}
