_: {
  programs.git = {
    enable = true;
    signing.format = null;
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = false; # .config/git/config で手動管理
  };

  # 既存の git/config, git/ignore を使用
  xdg.configFile."git/config".source = ../../../.config/git/config;
  xdg.configFile."git/ignore".source = ../../../.config/git/ignore;
}
