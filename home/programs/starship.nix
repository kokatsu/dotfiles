{...}: {
  programs.starship = {
    enable = true;
    enableZshIntegration = false; # 既存の.zshrcで管理
  };

  # starship.toml を直接シンボリックリンク
  xdg.configFile."starship.toml".source = ../../.config/starship.toml;
}
