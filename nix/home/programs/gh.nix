# GitHub CLI (gh) configuration
{isWSL, ...}: {
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
