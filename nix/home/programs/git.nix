_: {
  programs.git = {
    enable = true;
    signing.format = null;
  };

  # delta 本体は lazygit の diffRenderers が使う。git 側の連携は difftastic 移行で
  # 無効化しており (.config/git/config のコメントアウト部分)、テーマ設定も持たない
  programs.delta = {
    enable = true;
    enableGitIntegration = false; # .config/git/config で手動管理
  };

  xdg.configFile."git/config".source = ../../../.config/git/config;
  xdg.configFile."git/ignore".source = ../../../.config/git/ignore;
}
