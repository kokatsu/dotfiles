{
  pkgs,
  config,
  ...
}: let
  theme = (config.catppuccinLib.flavorNames config.catppuccin.flavor).spaced;
in {
  xdg.configFile = {
    "octorus/config.toml".source = (pkgs.formats.toml {}).generate "octorus-config" {
      editor = "nvim";
      diff = {
        inherit theme;
        bg_color = true;
        tab_width = 4;
      };
      keybindings = {
        approve = "a";
        request_changes = "r";
        comment = "c";
        suggestion = "s";
      };
      ai = {
        reviewer = "claude";
        reviewee = "claude";
        max_iterations = 10;
        timeout_secs = 600;
        reviewee_additional_tools = [
          "Skill"
        ];
      };
      shell = {
        timeout_secs = 60;
      };
    };
    # `or init` が $XDG_CONFIG_HOME/octorus/prompts/{reviewer,rereview,reviewee}.md を読む。
    "octorus/prompts".source = ../../../.config/octorus/prompts;
    "octorus/themes/${theme}.tmTheme".source = "${config.catppuccin.sources.bat}/${theme}.tmTheme";
  };
}
