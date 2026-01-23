# GitHub CLI (gh) configuration
{
  pkgs,
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isLinux;
  # WSL detection: Linux and kernel contains "microsoft" or "WSL"
  # In pure evaluation mode (CI), /proc/version access is forbidden, so skip WSL detection
  isWSL =
    if isCI
    then false
    else
      isLinux
      && builtins.pathExists /proc/version
      && builtins.match ".*[Mm]icrosoft.*" (builtins.readFile /proc/version) != null;
in {
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
      prefer_editor_prompt = "disabled";
      aliases = {
        co = "pr checkout";
      };
      # WSL: Open URLs in Windows browser
      # macOS/Linux: Use system default (empty string)
      browser =
        if isWSL
        then "cmd.exe /c start"
        else "";
    };
  };
}
