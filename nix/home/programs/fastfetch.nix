{
  lib,
  config,
  ...
}: let
  flavor = config.catppuccin.flavor;
  p = config.catppuccinLib.palettes.${flavor};

  rgb = c: "${toString c.rgb.r};${toString c.rgb.g};${toString c.rgb.b}";
  # Nix の文字列エスケープに \e / \u はないので、ESC は JSON 経由で作る
  esc = builtins.fromJSON "\"\\u001b\"";

  # nf-md-pokeball をパレット 10 色 × 3 周
  pokeballs = let
    cycle = with p; [red blue yellow mauve green pink sky peach lavender teal];
  in
    "{#1}"
    + lib.concatMapStringsSep " " (c: "{#38;2;${rgb c}}󰐝") (builtins.concatMap (_: cycle) [1 2 3])
    + "{#}{#}";

  heading = title: {
    type = "custom";
    format = "{#1}{#4}${esc}[38;2;${rgb p.mauve}m${title}:{#}{#}";
  };

  entry = type: key: {inherit type key;};

  break = {type = "break";};
in {
  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      logo = {
        type = "iterm";
        source = "\${XDG_CONFIG_HOME}/assets/logos/logo.gif";
        padding = {
          top = 6;
          left = 3;
          right = 4;
        };
        width = 30;
      };
      display = {
        separator = "";
        key.width = 30;
        size.binaryPrefix = "jedec";
      };
      modules = [
        {
          type = "custom";
          format = pokeballs;
        }
        break

        (heading "Hardware")
        (entry "cpu" "  CPU")
        (entry "gpu" "  GPU")
        {
          type = "disk";
          key = "  Disk ({mountpoint})";
          format = "{size-used} / {size-total} ({size-percentage})";
        }
        (entry "memory" "  Memory")
        (entry "swap" "  Swap")
        (entry "display" "  Display ({name})")
        (entry "battery" "  Battery")
        break

        (heading "Software")
        (entry "os" "  OS")
        (entry "kernel" "  Kernel")
        (entry "terminal" "  Terminal")
        (entry "shell" "  Shell")
        (entry "packages" "  Packages")
        (entry "font" "  Font")
        (entry "terminalfont" "  Terminal Font")
        break

        (heading "Connectivity")
        (entry "publicip" "  Public IP")
        (entry "localip" "  Local IP")
        (entry "dns" "  DNS")
        (entry "wifi" "  WiFi")
        break

        (heading "Other")
        (entry "users" "  User")
        (entry "datetime" "  Date & Time")
        (entry "uptime" "  Uptime")
        break

        {
          type = "custom";
          format = pokeballs;
        }
      ];
    };
  };
}
