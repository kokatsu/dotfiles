_: {
  programs.starship = {
    enable = true;
    enableZshIntegration = false;
    settings = fromTOML (builtins.readFile ../../../.config/starship.toml);
  };
}
