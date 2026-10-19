{
  config,
  inputs,
  pkgs,
  ...
}: let
  names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
in {
  # overlay や nixpkgs の差し替えを通すと helix.cachix.org の store path と
  # 一致せず Rust のフルビルドになる (flake.nix の helix input 参照)。
  home.packages = [inputs.helix.packages.${pkgs.stdenv.hostPlatform.system}.default];

  xdg.configFile = {
    # theme はビルトインの catppuccin_<flavor> を使う
    "helix/config.toml".text =
      "theme = \"${names.snake}\"\n\n"
      + builtins.readFile ../../../.config/helix/config.static.toml;
    "helix/languages.toml".source = ../../../.config/helix/languages.toml;
  };
}
