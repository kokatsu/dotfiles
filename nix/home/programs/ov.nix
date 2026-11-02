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
  xdg.configFile."ov/config.yaml".source = configFile;
}
