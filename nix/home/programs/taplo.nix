{
  # TAPLO_CONFIG (nix/home/default.nix) が指す全体の設定。CI は TAPLO_CONFIG を持たず
  # リポジトリ直下の .taplo.toml を読むので、同じファイルを配置して両者を揃える。
  xdg.configFile."taplo/taplo.toml".source = ../../../.taplo.toml;
}
