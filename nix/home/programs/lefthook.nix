{config, ...}: let
  p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
  globalConfig = "${config.xdg.configHome}/lefthook/global.json";
in {
  # Lefthook にはユーザー設定の自動探索がないため、共通設定をメイン設定として
  # 指定し、リポジトリ側の設定を extends で重ねる。
  home.sessionVariables.LEFTHOOK_CONFIG = globalConfig;

  xdg.configFile."lefthook/global.json".text = builtins.toJSON {
    colors = {
      cyan = p.sky.hex;
      gray = p.overlay0.hex;
      green = p.green.hex;
      red = p.red.hex;
      yellow = p.yellow.hex;
    };

    # Lefthook が対応する全メイン設定名。存在しない glob は無視される。
    extends = [
      "lefthook.y*"
      ".lefthook.y*"
      "lefthook.toml"
      ".lefthook.toml"
      "lefthook.json*"
      ".lefthook.json*"
      ".config/lefthook.y*"
      ".config/lefthook.toml"
      ".config/lefthook.json*"
    ];
  };
}
