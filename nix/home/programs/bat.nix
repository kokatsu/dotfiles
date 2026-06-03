{pkgs, ...}: {
  programs.bat = {
    enable = true;
    # pkl: bat は syntect 経由で .sublime-syntax のみ対応 (.tmLanguage は不可)。
    # Package Control "Pkl (Pickle)" の公式ソースから取得し、cache は自動再構築。
    syntaxes.pkl = {
      src = pkgs.fetchFromGitHub {
        owner = "serjan-nasredin";
        repo = "pkl.tmbundle";
        rev = "v0.0.6";
        hash = "sha256-w3iGJlyHyjve++H03gX7qYOEx7IVUeNUVFRE/AVq2L8=";
      };
      file = "syntaxes/Pkl.sublime-syntax";
    };
    config = {
      italic-text = "always";
      paging = "never";
      map-syntax = [
        # TODO(human): 拡張子を持たない pkl 関連ファイルの map-syntax を追加
        "justfile:Makefile"
        "*.json5:JavaScript"
        "deno.lock:JSON"
        "*.tmTheme:XML"
        ".yamlfmt:YAML"
        ".ripgreprc:Bourne Again Shell (bash)"
        "*.markdownlintignore:Git Ignore"
        ".psqlrc:SQL"
        "inputrc:INI"
        "btop.conf:INI"
        "*.theme:INI"
        "**/ghostty/config:INI"
        "**/ghostty/themes/*:INI"
      ];
    };
  };
}
