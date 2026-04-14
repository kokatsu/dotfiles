{config, ...}: {
  programs.git = {
    enable = true;
    signing.format = null;
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = false; # .config/git/config で手動管理
  };

  # git/config は delta の features 行のみ flavor に追従させる
  xdg.configFile."git/config".text = let
    names = config.catppuccinLib.flavorNames config.catppuccin.flavor;
    staticContent = builtins.readFile ../../../.config/git/config;
  in
    builtins.replaceStrings
    ["features = catppuccin-mocha"]
    ["features = ${names.kebab}"]
    staticContent;
  xdg.configFile."git/ignore".source = ../../../.config/git/ignore;
}
