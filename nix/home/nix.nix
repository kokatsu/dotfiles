{pkgs, ...}: {
  # ~/.config/nix/nix.conf を Home Manager 管理下に置く。
  # このファイルが失われると activation の installPackages が呼ぶ
  # `nix profile install` が nix-command 無効で失敗する。
  nix = {
    # nix.settings から nix.conf を生成する際の検証にのみ使われ、
    # プロファイルにはインストールされない。
    package = pkgs.nix;

    # macOS では use-xdg-base-directories を nix/darwin/default.nix のシステム設定に置く。
    # ユーザー設定の値は daemon へ転送され、trusted user でないと毎回警告が出るため。
    assumeXdg = pkgs.stdenv.hostPlatform.isDarwin;

    settings =
      {
        # extra- 接頭辞にして、システム側 (Determinate Nix 等) の
        # experimental-features を上書きせず追記する。
        extra-experimental-features = ["nix-command" "flakes"];

        # 独立した derivation を並列化しつつ、12 スレッド環境で
        # max-jobs * cores が利用可能スレッド数を超えないようにする。
        max-jobs = 4;
        cores = 3;
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        # ~/.nix-profile と ~/.nix-defexpr を $XDG_STATE_HOME/nix へ移す。
        # Home Manager は home.profileDirectory と NIX_PATH をこれに合わせて切り替える。
        use-xdg-base-directories = true;

        # CI が main ブランチで構築した custom package を再利用する。
        # Linux は single-user Nix のため、ユーザー設定を source of truth とする。
        # helix は上流 CI が master の push ごとに push している。
        extra-substituters = ["https://kokatsu.cachix.org" "https://helix.cachix.org"];
        extra-trusted-public-keys = [
          "kokatsu.cachix.org-1:womBGQiv46ieMIq9Lll7fa06bN0CMKMjIEDIjvp8+rI="
          "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
        ];
      };
  };
}
