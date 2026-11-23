{
  pkgs,
  lib,
  config,
  validDotfilesDir,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  flavor = config.catppuccin.flavor;
  p = config.catppuccinLib.palettes.${flavor};
  names = config.catppuccinLib.flavorNames flavor;
in {
  home.file =
    {
      # nvim: mkOutOfStoreSymlinkでdotfilesリポジトリを直接リンク
      # これによりlazy-lock.jsonへの書き込みがリポジトリに反映される
      ".config/nvim" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/nvim";
        force = true;
      };
      ".config/git-graph/models/catppuccin-${flavor}.toml".text =
        # toml
        ''
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
      ".config/gomi/config.yaml".text =
        # yaml
        ''
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
      ".config/bulletty/feeds.opml".source = ../../.config/bulletty/feeds.opml;
      ".config/bulletty/feeds-forum.opml".source = ../../.config/bulletty/feeds-forum.opml;
      # feeds*.opml だけを bin/feed-watch が読む。bulletty へ import したいが
      # 未読カウントには出したくないフィードはこちらへ置く
      ".config/bulletty/bulletty-only.opml".source = ../../.config/bulletty/bulletty-only.opml;
      # bin: ユーザースクリプト
      # mkOutOfStoreSymlink で直接リンクし、スクリプト編集がリポジトリに反映される
      ".local/bin/scripts" = {
        source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/bin";
        force = true;
      };
    }
    # Docker CLI plugins (macOSではOrbStackが管理)
    // lib.optionalAttrs (!isDarwin) {
      ".config/docker/cli-plugins/docker-buildx".source = "${pkgs.docker-buildx}/bin/docker-buildx";
      ".config/docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/bin/docker-compose";
    };

  xdg.configFile = {
    "wget/wgetrc".text = ''
      hsts_file = ${config.xdg.stateHome}/wget/hsts
    '';
    "npm/global-npmrc".text = ''
      min-release-age=7
      strict-allow-scripts=true
    '';
    "pnpm/config.yaml".text =
      # yaml
      ''
        minimumReleaseAge: 10080
        trustPolicy: no-downgrade
        strictDepBuilds: true
      '';
    ".bunfig.toml".text =
      # toml
      ''
        [install]
        minimumReleaseAge = 604800
      '';
  };

  # less と node と wget と python と sqlite3 は状態ファイルの親ディレクトリを作らず、
  # 無ければ書き込みを黙って諦める。
  xdg.stateFile = {
    "less/.keep".text = "";
    "node/.keep".text = "";
    "wget/.keep".text = "";
    "vim/.keep".text = "";
    "python/.keep".text = "";
    "sqlite/.keep".text = "";
  };
}
