# hermes-agent flake の package を dotfiles 側 pkgs に注入
{inputs}: {
  hermes-agent = _final: prev: let
    hermesAgentPkgs = inputs.hermes-agent.packages.${prev.stdenv.hostPlatform.system};
  in {
    hermes-agent = hermesAgentPkgs.default;
  };
}
