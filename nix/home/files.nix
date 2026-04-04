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
}
