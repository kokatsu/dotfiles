{
  pkgs,
  lib,
  config,
  isWSL,
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
  names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
in {
  home = {
    file = {
      ".config/wezterm/background.lua".text = let
        staticContent = builtins.readFile ../../../.config/wezterm/background.static.lua;
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
      ".config/wezterm/colors.lua".text = ''
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
      ".config/wezterm/format.lua".source = ../../../.config/wezterm/format.lua;
      ".config/wezterm/keybinds.lua".source = ../../../.config/wezterm/keybinds.lua;
      ".config/wezterm/mac.lua".source = ../../../.config/wezterm/mac.lua;
      ".config/wezterm/platform.lua".source = ../../../.config/wezterm/platform.lua;
      ".config/wezterm/stylua.toml".source = ../../../.config/wezterm/stylua.toml;
      ".config/wezterm/wezterm.lua".source = ../../../.config/wezterm/wezterm.lua;
      ".config/wezterm/windows.lua".source = ../../../.config/wezterm/windows.lua;
    };

    # WSLからWindows側へ設定を再帰コピーする。
    activation.copyWezTermConfig = lib.mkIf isWSL (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WINUSER=$(/mnt/c/Windows/System32/cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
      WEZTERM_DIR="/mnt/c/Users/$WINUSER/.config/wezterm"
      SRC_DIR="$HOME/.config/wezterm"
      if [ -n "$WINUSER" ] && [ -d "/mnt/c/Users/$WINUSER" ]; then
        $DRY_RUN_CMD mkdir -p "$WEZTERM_DIR"
        find -L "$SRC_DIR" -type f -name '*.lua' | while IFS= read -r f; do
          rel="''${f#$SRC_DIR/}"
          dst="$WEZTERM_DIR/$rel"
          $DRY_RUN_CMD mkdir -p "$(dirname "$dst")"
          $DRY_RUN_CMD cp -fL "$f" "$dst"
        done
      fi
    '');

    # Dockから起動できるようNix storeのapp bundleを/Applicationsへリンクする。
    activation.linkWezTermApp = lib.mkIf (isDarwin && !isCI) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WEZTERM_APP="${pkgs.wezterm}/Applications/WezTerm.app"
      if [ -d "$WEZTERM_APP" ]; then
        $DRY_RUN_CMD rm -f /Applications/WezTerm.app
        $DRY_RUN_CMD ln -sf "$WEZTERM_APP" /Applications/WezTerm.app
      fi
    '');
  };
}
