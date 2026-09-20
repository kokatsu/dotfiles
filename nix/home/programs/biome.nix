{
  pkgs,
  lib,
  ...
}: let
  settings = {
    "$schema" = "https://biomejs.dev/schemas/2.5.11/schema.json";
    linter = {
      enabled = true;
      rules = {
        recommended = true;
      };
    };
    formatter = {
      useEditorconfig = true;
    };
    javascript = {
      formatter = {
        quoteStyle = "single";
      };
    };
  };
  configFile = (pkgs.formats.json {}).generate "biome-config.json" settings;
  # 適用前や CI でも使うリポジトリ設定は自己完結させ、共通項目の一致を評価時に検証する。
  # builtins.fromJSON で読めるよう、.biome.jsonc はコメントなしの JSON として保つ。
  repositorySettings = builtins.fromJSON (builtins.readFile ../../../.biome.jsonc);
in {
  assertions = [
    {
      assertion = builtins.removeAttrs repositorySettings ["files" "vcs"] == settings;
      message = "Shared Biome settings differ between .biome.jsonc and nix/home/programs/biome.nix. Keep them in sync; only files and vcs are repository-specific.";
    }
  ];
  xdg.configFile."biome".source = pkgs.linkFarm "biome-config-directory" [
    {
      name = ".biome.jsonc";
      path = configFile;
    }
  ];
  # macOS の Biome グローバル設定は ~/Library/Application Support/biome/ に置く。
  home.file = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    "Library/Application Support/biome/.biome.jsonc".source = configFile;
  };
}
