{pkgs, ...}: let
  configFile = (pkgs.formats.toml {}).generate "moxide-config" {
    dailynote = "%Y/%m/%Y-%m-%d";
    daily_notes_folder = ".kokatsu/daily";
    # 依存パッケージ同梱の .md がローカルの .md 全体の 72.4% (15,661/21,635) を占め、
    # vault のインデックス作成に CPU 119.8 秒・VmHWM 221.7MB を要していたため除外する。
    # 除外後は CPU 1.6 秒・VmHWM 20.5MB。
    # ディレクトリ名を深さ問わずマッチする。隠しディレクトリは既定で走査対象外。
    excluded_folders = [
      "node_modules"
    ];
  };
in {
  # 既存のディレクトリ単位のリンクを維持する。
  xdg.configFile."moxide".source = pkgs.linkFarm "moxide-config-directory" [
    {
      name = "settings.toml";
      path = configFile;
    }
  ];
}
