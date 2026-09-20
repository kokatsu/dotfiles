{pkgs, ...}: let
  configFile = (pkgs.formats.toml {}).generate "taplo-config" {
    formatting = {
      column_width = 100;
      trailing_newline = true;
    };
  };
in {
  # 既存のディレクトリ単位のリンクを維持する。
  xdg.configFile."taplo".source = pkgs.linkFarm "taplo-config-directory" [
    {
      name = "taplo.toml";
      path = configFile;
    }
  ];
}
