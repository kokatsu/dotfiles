# hermes-agent flake の package を dotfiles 側 pkgs に注入
{inputs}: {
  hermes-agent = _final: prev: let
    # uv2nix はまだ非推奨の stdenv.isDarwin/isLinux を参照している。
    # Hermes 専用 package scope だけに hostPlatform 由来の互換属性を追加し、
    # 他の nixpkgs package へ影響を広げず評価警告を抑制する。
    compatPkgs = prev.extend (_compatFinal: compatPrev: {
      stdenv =
        compatPrev.stdenv
        // {
          inherit (compatPrev.stdenv.hostPlatform) isDarwin isLinux;
        };
    });
    hermesInputs = inputs.hermes-agent.inputs;
  in {
    # v2026.7 以降の default は全 optional group 入りの full で、CI の macOS ビルドが
    # 60 分に収まらない。使っていない voice/tts/messaging 等を含まない軽量版を使う
    # (v2026.6.19 以前は minimal が未定義で default が同等物)。
    # 統合を追加するときは minimal.override {extraDependencyGroups = [...];} を使う。
    hermes-agent = compatPkgs.callPackage "${inputs.hermes-agent}/nix/hermes-agent.nix" {
      inherit (hermesInputs) uv2nix pyproject-nix pyproject-build-systems;
      npm-lockfile-fix = hermesInputs.npm-lockfile-fix.packages.${prev.stdenv.hostPlatform.system}.default;
      rev = inputs.hermes-agent.rev or null;
    };
  };
}
