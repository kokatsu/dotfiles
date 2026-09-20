{pkgs, ...}: let
  configFile = (pkgs.formats.yaml {}).generate "ov-config" {
    SmartCaseSensitive = true;
    Incsearch = true;
    WrapMode = true;
    QuitSmall = true;
    Mode = {
      markdown = {
        Header = 3;
        AlternateRows = true;
        ColumnMode = true;
        ColumnDelimiter = "|";
      };
      psql = {
        Header = 2;
        AlternateRows = true;
        ColumnMode = true;
        ColumnDelimiter = "|";
      };
      mysql = {
        Header = 3;
        AlternateRows = true;
        ColumnMode = true;
        ColumnDelimiter = "|";
      };
    };
  };
in {
  # 既存のディレクトリ単位のリンクを維持する。
  xdg.configFile."ov".source = pkgs.linkFarm "ov-config-directory" [
    {
      name = "config.yaml";
      path = configFile;
    }
  ];
}
