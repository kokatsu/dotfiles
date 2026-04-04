_: {
  programs.bat = {
    enable = true;
    config = {
      italic-text = "always";
      paging = "never";
      map-syntax = [
        "justfile:Makefile"
        "*.json5:JavaScript"
        "deno.lock:JSON"
        "*.tmTheme:XML"
        ".yamlfmt:YAML"
        ".ripgreprc:Bourne Again Shell (bash)"
        "*.markdownlintignore:Git Ignore"
        ".psqlrc:SQL"
        "btop.conf:INI"
        "*.theme:INI"
        "**/ghostty/config:INI"
        "**/ghostty/themes/*:INI"
      ];
    };
  };
}
