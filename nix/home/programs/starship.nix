{config, ...}: let
  flavor = config.catppuccin.flavor;
  paletteName = "catppuccin_${flavor}";
  palette = builtins.mapAttrs (_: color: color.hex) config.catppuccinLib.palettes.${flavor};
in {
  # catppuccin/nix は生成済み TOML を評価時に読み込むため IFD が発生する。
  # 同じ palette を既存の純粋な Nix palette 定義から組み立てる。
  catppuccin.starship.enable = false;

  programs.starship = {
    enable = true;
    enableZshIntegration = false;
    settings =
      fromTOML (builtins.readFile ../../../.config/starship.toml)
      // {
        palette = paletteName;
        palettes.${paletteName} = palette;
      };
  };
}
