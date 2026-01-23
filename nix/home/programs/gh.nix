# GitHub CLI (gh) configuration
{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin isLinux;
  # WSL detection: Linux and kernel contains "microsoft" or "WSL"
  # Using builtins.tryEval to handle cases where /proc/version is not readable
  procVersion = builtins.tryEval (builtins.readFile /proc/version);
  isWSL =
    isLinux
    && procVersion.success
    && builtins.match ".*[Mm]icrosoft.*" procVersion.value != null;
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
