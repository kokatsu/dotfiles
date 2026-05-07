# cli-tools flake の packages を dotfiles 側 pkgs に注入
{inputs}: {
  cli-tools = _final: prev: let
    cliToolsPkgs = inputs.cli-tools.packages.${prev.stdenv.hostPlatform.system};
  in {
    inherit (cliToolsPkgs) daily memo;
  };
}
