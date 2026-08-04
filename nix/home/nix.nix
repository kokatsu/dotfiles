{pkgs, ...}: {
  # ~/.config/nix/nix.conf を Home Manager 管理下に置く。
  # このファイルが失われると activation の installPackages が呼ぶ
  # `nix profile install` が nix-command 無効で失敗する。
  nix = {
    # nix.settings から nix.conf を生成する際の検証にのみ使われ、
    # プロファイルにはインストールされない。
    package = pkgs.nix;

    settings = {
      # extra- 接頭辞にして、システム側 (Determinate Nix 等) の
      # experimental-features を上書きせず追記する。
      extra-experimental-features = ["nix-command" "flakes"];
    };
  };
}
