{pkgs, ...}: let
  configFile = (pkgs.formats.toml {}).generate "taplo-config" {
    formatting = {
      column_width = 100;
      trailing_newline = true;
    };
  };
in {
  xdg.configFile."taplo/taplo.toml".source = configFile;
}
