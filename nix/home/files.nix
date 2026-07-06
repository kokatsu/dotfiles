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
      # fff.nvim: Nix ビルド版 (Rust バックエンド同梱) を lazy.nvim の dir 参照用に配置
      ".local/share/nvim/nix-plugins/fff.nvim".source = pkgs.vimPlugins.fff-nvim;
      # settings.json: mkOutOfStoreSymlink でリポジトリを直接リンク
      # これにより /effort などランタイムでの書き込みがリポジトリに反映される
      ".config/claude/settings.json" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/claude/settings.json";
        force = true;
      };
      ".config/claude/CLAUDE.md".source = ../../.config/claude/.CLAUDE.md;
      ".config/claude/skills".source = ../../.config/claude/skills;
      ".config/claude/commands".source = ../../.config/claude/commands;
      ".config/claude/rules".source = ../../.config/claude/rules;
      ".config/claude/file-suggestion.sh" = {
        source = ../../.config/claude/file-suggestion.sh;
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
      ".config/claude/hooks/herdr-agent-state.sh" = {
        source = ../../.config/claude/hooks/herdr-agent-state.sh;
        executable = true;
      };
      ".config/claude/hooks/notify.sh" = {
        source = ../../.config/claude/hooks/notify.sh;
        executable = true;
      };
      # Claude Code キーバインド (CLAUDE_CONFIG_DIR で ~/.config/claude を使用)
      ".config/claude/keybindings.json".source = ../../.config/claude/keybindings.json;

      # Claude Code カスタムテーマ (2.1.118+): 4 flavor を ~/.config/claude/themes/ に生成
      # 実体は `home.file` ブロック末尾で `// (builtins.listToAttrs ...)` として合流
      # 起動中もファイルウォッチで反映。`/theme` で "Catppuccin <Flavor>" を選択

      # Codex: built-in skills (.system) を残すため、共有したい skill だけを個別にリンク
      ".config/codex/skills/browser-research".source = ../../.config/codex/skills/browser-research;

      # Codex: herdr integration (`herdr integration install codex` の生成物を nix 管理化。
      # integration 更新時は install し直して repo へコピーする。config.toml 側は
      # [features] の `hooks = true` が対応)
      ".config/codex/herdr-agent-state.sh" = {
        source = ../../.config/codex/herdr-agent-state.sh;
        executable = true;
      };
      ".config/codex/hooks.json".text = builtins.toJSON {
        hooks.SessionStart = [
          {
            hooks = [
              {
                command = "bash '${config.xdg.configHome}/codex/herdr-agent-state.sh' session";
                timeout = 10;
                type = "command";
              }
            ];
          }
        ];
      };

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
      # herdr: 組み込みテーマは catppuccin-mocha/catppuccin-latte 等のフレーバー別名で
      # 用意されている (--default-config のコメントには載っていないが実機で受理を確認済み)。
      # Ghostty と同じく catppuccin.flavor から導出する。accent はアクティブペイン枠色を
      # 担うキー (ui.accent)。他ツールと同じ blue で揃える
      #
      # [[keys.command]] は tmux の Alt+v/c/g/h ポップアップの herdr 移植版
      # (.config/herdr/scripts/*.sh)。tmux 版と違い bind 時点での条件分岐が
      # できないため claude/codex 判定はスクリプト内で実行時に行う。
      #
      # [ui.toast] は Claude Code Stop/Notification hook の通知 (tmux DCS
      # passthrough 依存、herdr 配下では機能しない) の代わりに herdr ネイティブの
      # 通知機構を使うためのもの。
      #
      # [keys] は herdr を macOS の常用マルチプレクサとした再構築 (WezTerm は
      # タブ/ペイン管理を全撤去した薄い GUI シェル) に合わせた配置:
      # - prefix+t 新タブは旧 WezTerm (ctrl+t) の筋肉記憶
      # - alt+矢印 focus_pane は tmux/WezTerm 時代の direct キーを踏襲
      #   (WezTerm 側の OPT+矢印 SendString と Alt 系バインドは撤去済みが前提)
      # - alt+1..9 focus_agent は左右どちらの Option でも可
      #   (mac.lua で send_composed_key_* = false)
      # 明示していないキーは herdr デフォルト (split_vertical=prefix+v,
      # split_horizontal=prefix+minus, settings=prefix+s, zoom=prefix+z,
      # close_pane=prefix+x, switch_tab=prefix+1..9, workspace_picker=prefix+w,
      # new_worktree=prefix+shift+g, edit_scrollback=prefix+e,
      # open_notification_target=prefix+o 等) を継承。
      #
      # [experimental] は日本語 IME 対策: prefix モード中の ASCII 入力ソース切替と、
      # Claude Code/codex ペインでの IME 候補窓追従。
      ".config/herdr/config.toml".text = let
        names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
        p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
        scriptsDir = "${config.xdg.configHome}/herdr/scripts";
      in ''
        [theme]
        name = "${names.kebab}"

        [ui]
        accent = "${p.blue.hex}"
        show_agent_labels_on_pane_borders = true

        [ui.toast]
        delivery = "terminal"

        [keys]
        prefix = "ctrl+space"
        new_tab = "prefix+t"
        focus_pane_left = "alt+left"
        focus_pane_down = "alt+down"
        focus_pane_up = "alt+up"
        focus_pane_right = "alt+right"
        last_pane = "prefix+space"
        focus_agent = "alt+1..9"
        previous_workspace = "prefix+comma"
        next_workspace = "prefix+period"

        [experimental]
        switch_ascii_input_source_in_prefix = true
        reveal_hidden_cursor_for_cjk_ime = true
        cjk_ime_agents = ["claude", "codex"]

        [[keys.command]]
        key = "alt+v"
        type = "pane"
        command = "${scriptsDir}/prompt-edit.sh"
        description = "Claude Code: プロンプト編集"

        [[keys.command]]
        key = "alt+c"
        type = "pane"
        command = "${scriptsDir}/path-pick-fzf.sh"
        description = "パス選択 (fzf)"

        [[keys.command]]
        key = "alt+g"
        type = "pane"
        command = "${scriptsDir}/path-pick-broot.sh"
        description = "パス選択 (broot)"

        [[keys.command]]
        key = "alt+h"
        type = "pane"
        command = "${scriptsDir}/octorus-history.sh"
        description = "Octorus Rally 履歴"

        # alt+y は WSL では WezTerm windows_specific (PowerShell タブ) が先に
        # 捕捉するため macOS 専用
        [[keys.command]]
        key = "alt+y"
        type = "pane"
        command = "${scriptsDir}/yazi-pane.sh"
        description = "Yazi"

        # alt+l は nvim mini.move (<M-l>) を奪うため prefix 側に置く
        [[keys.command]]
        key = "prefix+l"
        type = "pane"
        command = "${scriptsDir}/lazygit-pane.sh"
        description = "Lazygit"

        # 旧 WezTerm Alt+r の移植。feed-watch のデータ生成 (systemd timer) が
        # WSL 限定のため実質 WSL 専用 (macOS ではデータなしメッセージのみ)
        [[keys.command]]
        key = "alt+r"
        type = "pane"
        command = "${scriptsDir}/feed-open.sh"
        description = "未読フィードを開く"
      '';
      ".config/herdr/scripts/prompt-edit.sh" = {
        source = ../../.config/herdr/scripts/prompt-edit.sh;
        executable = true;
      };
      ".config/herdr/scripts/path-pick-fzf.sh" = {
        source = ../../.config/herdr/scripts/path-pick-fzf.sh;
        executable = true;
      };
      ".config/herdr/scripts/path-pick-broot.sh" = {
        source = ../../.config/herdr/scripts/path-pick-broot.sh;
        executable = true;
      };
      ".config/herdr/scripts/octorus-history.sh" = {
        source = ../../.config/herdr/scripts/octorus-history.sh;
        executable = true;
      };
      ".config/herdr/scripts/yazi-pane.sh" = {
        source = ../../.config/herdr/scripts/yazi-pane.sh;
        executable = true;
      };
      ".config/herdr/scripts/lazygit-pane.sh" = {
        source = ../../.config/herdr/scripts/lazygit-pane.sh;
        executable = true;
      };
      ".config/herdr/scripts/feed-open.sh" = {
        source = ../../.config/herdr/scripts/feed-open.sh;
        executable = true;
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
    # Hermes Agent カスタムスキン: 4 flavor を生成
    # YAML は JSON のスーパーセットなので builtins.toJSON 出力をそのまま .yaml として読ませる
    // (let
      mkHermesSkin = flavor: let
        p = config.catppuccinLib.palettes.${flavor};
        names = config.catppuccinLib.flavorNames flavor;
      in
        builtins.toJSON {
          name = "catppuccin-${flavor}";
          description = "Catppuccin ${names.capitalized} for Hermes Agent";
          colors = {
            banner_border = p.mauve.hex;
            banner_title = p.yellow.hex;
            banner_accent = p.teal.hex;
            banner_dim = p.overlay1.hex;
            banner_text = p.text.hex;
            ui_accent = p.mauve.hex;
            ui_label = p.sapphire.hex;
            ui_ok = p.green.hex;
            ui_error = p.red.hex;
            ui_warn = p.peach.hex;
            prompt = p.text.hex;
            input_rule = p.surface1.hex;
            response_border = p.mauve.hex;
            status_bar_bg = p.mantle.hex;
            status_bar_text = p.subtext1.hex;
            status_bar_strong = p.yellow.hex;
            status_bar_dim = p.overlay0.hex;
            status_bar_good = p.green.hex;
            status_bar_warn = p.yellow.hex;
            status_bar_bad = p.peach.hex;
            status_bar_critical = p.red.hex;
            session_label = p.sapphire.hex;
            session_border = p.overlay0.hex;
            voice_status_bg = p.mantle.hex;
            selection_bg = p.surface1.hex;
            completion_menu_bg = p.mantle.hex;
            completion_menu_current_bg = p.surface1.hex;
            completion_menu_meta_bg = p.mantle.hex;
            completion_menu_meta_current_bg = p.surface1.hex;
          };
        };
    in
      builtins.listToAttrs (map (flavor: {
        name = ".config/hermes/skins/catppuccin-${flavor}.yaml";
        value = {text = mkHermesSkin flavor;};
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
