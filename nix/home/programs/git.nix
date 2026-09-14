_: {
  programs.git = {
    enable = true;
    signing.format = null;
  };

  # lazygit の diffRenderers が delta を呼ぶ (git 側は difftastic)
  programs.delta = {
    enable = true;
    enableGitIntegration = false;
  };

  xdg.configFile."git/config".source = ../../../.config/git/config;
  xdg.configFile."git/ignore".source = ../../../.config/git/ignore;
}
