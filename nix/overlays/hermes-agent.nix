# hermes-agent flake の package を dotfiles 側 pkgs に注入
{inputs}: {
  hermes-agent = _final: prev: let
    hermesAgentPkgs = inputs.hermes-agent.packages.${prev.stdenv.hostPlatform.system};
  in {
    # v2026.7 以降の default は全 optional group 入りの full で、CI の macOS ビルドが
    # 60 分に収まらない。使っていない voice/tts/messaging 等を含まない軽量版を使う
    # (v2026.6.19 以前は minimal が未定義で default が同等物)。
    # 統合を追加するときは minimal.override {extraDependencyGroups = [...];} を使う。
    hermes-agent = hermesAgentPkgs.minimal or hermesAgentPkgs.default;
  };
}
