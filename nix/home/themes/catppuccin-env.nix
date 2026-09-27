{config, ...}: let
  inherit (config.catppuccin) flavor sources;
in {
  # catppuccin/nix はテーマの store パスをそのまま sessionVariables に書くが、
  # 起動時の環境を持ち続ける長寿命プロセス (herdr サーバー等) では旧パスが GC で消え、
  # そこから起動した fzf などが読み込みに失敗する。~/.config の固定パスを経由させ、
  # 常に現行世代を指すようにする
  catppuccin.fzf.enable = false;
  catppuccin.glamour.enable = false;

  xdg.configFile = {
    "fzf/catppuccin.rc".source = "${sources.fzf}/catppuccin-fzf-${flavor}.rc";
    "glamour/catppuccin.json".source = "${sources.glamour}/catppuccin-${flavor}.json";
  };

  home.sessionVariables = {
    FZF_DEFAULT_OPTS_FILE = "${config.xdg.configHome}/fzf/catppuccin.rc";
    GLAMOUR_STYLE = "${config.xdg.configHome}/glamour/catppuccin.json";
  };
}
