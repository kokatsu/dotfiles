_: {
  programs.git = {
    enable = true;
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  # 既存の git/config を使用
  xdg.configFile."git/config".source = ../../../.config/git/config;
}
