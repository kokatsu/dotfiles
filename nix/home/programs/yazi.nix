{
  config,
  lib,
  pkgs,
  ...
}: let
  # 旧構成の .config/yazi 全体へのリンクをそのまま置換する。
  # 個別リンクへ変えると activation が旧リンクを辿り、作業ツリーを書き換えてしまう。
  files =
    ["yazi.toml" "keymap.toml" "theme.toml" "init.lua" "git-changes.sh"]
    ++ map (name: "plugins/${name}.yazi") (builtins.attrNames config.programs.yazi.plugins)
    ++ map (name: "flavors/${name}.yazi") (builtins.attrNames config.programs.yazi.flavors);
  managedFiles = map (name: "yazi/${name}") files;
in {
  assertions = [
    {
      # Home Manager が出力を追加した場合も、ディレクトリ内の配置を漏らさない。
      assertion =
        lib.sort builtins.lessThan managedFiles
        == lib.filter (lib.hasPrefix "yazi/") (builtins.attrNames config.xdg.configFile);
      message = "Yazi config files differ from the linkFarm file list. Update nix/home/programs/yazi.nix to include every yazi/ entry.";
    }
  ];
  # vendored sources: yazi-rs/plugins 044c3cc, kokatsu/ansi-preview 865f404,
  # yazi-rs/flavors 20b47bf。更新はリポジトリのソースを更新して switch する。
  # ya pkg は使用しない。シェルの yi 関数は既存の functions.zsh が管理する。
  programs.yazi = {
    enable = true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    enableZshIntegration = false;
    settings = {
      mgr = {
        linemode = "size";
        ratio = [
          1
          3
          4
        ];
        show_hidden = true;
        sort_by = "natural";
        sort_dir_first = true;
      };
      preview = {
        max_width = 2400;
        max_height = 3600;
      };
      opener = {
        edit = [
          {
            run = "nvim %s";
            block = true;
            for = "unix";
          }
        ];
      };
      plugin = {
        prepend_previewers = [
          {
            url = "*.ans";
            run = "ansi-preview";
          }
          {
            url = "*.ansi";
            run = "ansi-preview";
          }
        ];
        prepend_fetchers = [
          {
            url = "*";
            run = "git";
            group = "git";
          }
          {
            url = "*/";
            run = "git";
            group = "git";
          }
        ];
      };
    };
    keymap = {
      mgr = {
        prepend_keymap = [
          {
            on = "l";
            run = "plugin smart-enter";
            desc = "Enter directory or open file";
          }
          {
            on = "<Enter>";
            run = "plugin smart-enter";
            desc = "Enter directory or open file";
          }
          {
            on = "f";
            run = "plugin smart-filter";
            desc = "Smart filter";
          }
          {
            on = "<C-h>";
            run = "hidden toggle";
            desc = "Toggle hidden files";
          }
          {
            on = "T";
            run = "plugin toggle-pane max-preview";
            desc = "Maximize or restore the preview pane";
          }
          {
            on = "S";
            run = "shell '$SHELL' --block";
            desc = "Open shell here";
          }
          {
            on = "e";
            run = "shell '$EDITOR %s' --block";
            desc = "Edit with $EDITOR";
          }
          {
            on = "b";
            run = "shell 'if command -v wslview >/dev/null 2>&1; then wslview %s; elif [ \"$(uname)\" = \"Darwin\" ]; then open %s; else xdg-open %s; fi' --orphan";
            desc = "Open with default app";
          }
          {
            on = [
              "g"
              "s"
            ];
            run = "plugin vcs-files";
            desc = "List Git-changed files";
          }
          {
            on = [
              "g"
              "j"
            ];
            run = "shell 'bash \"$HOME/.config/yazi/git-changes.sh\"' --block";
            desc = "Jump to a Git-changed file (fzf)";
          }
          {
            on = "+";
            run = "plugin zoom 1";
            desc = "Zoom in hovered file";
          }
          {
            on = "-";
            run = "plugin zoom -1";
            desc = "Zoom out hovered file";
          }
          {
            on = "H";
            run = "arrow 0vp";
            desc = "Move cursor to the top of viewport";
          }
          {
            on = "M";
            run = "arrow 50vp";
            desc = "Move cursor to the middle of viewport";
          }
          {
            on = "L";
            run = "arrow 100vp";
            desc = "Move cursor to the bottom of viewport";
          }
          {
            on = "<C-o>";
            run = "back";
            desc = "Back to previous directory";
          }
          {
            on = "<C-p>";
            run = "forward";
            desc = "Forward to next directory";
          }
        ];
      };
    };
    theme = {
      flavor = {
        dark = "catppuccin-mocha";
        light = "catppuccin-latte";
      };
    };
    initLua = ../../../.config/yazi/init.lua;
    plugins = {
      ansi-preview = ../../../.config/yazi/plugins/ansi-preview.yazi;
      git = ../../../.config/yazi/plugins/git.yazi;
      smart-enter = ../../../.config/yazi/plugins/smart-enter.yazi;
      smart-filter = ../../../.config/yazi/plugins/smart-filter.yazi;
      toggle-pane = ../../../.config/yazi/plugins/toggle-pane.yazi;
      vcs-files = ../../../.config/yazi/plugins/vcs-files.yazi;
      zoom = ../../../.config/yazi/plugins/zoom.yazi;
    };
    flavors = {
      catppuccin-latte = ../../../.config/yazi/flavors/catppuccin-latte.yazi;
      catppuccin-mocha = ../../../.config/yazi/flavors/catppuccin-mocha.yazi;
    };
  };
  xdg.configFile =
    lib.genAttrs managedFiles (_: {enable = false;})
    // {
      "yazi" = {
        source = pkgs.linkFarm "yazi-config-directory" (map (name: {
            inherit name;
            path = config.xdg.configFile."yazi/${name}".source;
          })
          files);
        force = true;
      };
      "yazi/git-changes.sh" = {
        enable = false;
        source = ../../../.config/yazi/git-changes.sh;
      };
    };
}
