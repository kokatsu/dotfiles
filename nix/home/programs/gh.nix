# GitHub CLI (gh) configuration
{isWSL, ...}: {
  programs.gh = {
    enable = true;
    # 旧 git/config の source 配置では自動生成 helper は使われていなかった。
    # 認証は引き続き git/config.local で管理する。
    gitCredentialHelper.enable = false;
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
