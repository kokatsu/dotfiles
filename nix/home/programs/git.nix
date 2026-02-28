_: {
  programs.git = {
    enable = true;
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  # 既存の git/config, git/ignore を使用
  xdg.configFile."git/config".source = ../../../.config/git/config;
  xdg.configFile."git/ignore".source = ../../../.config/git/ignore;
}
