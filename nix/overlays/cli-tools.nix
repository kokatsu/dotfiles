# cli-tools flake の packages を dotfiles 側 pkgs に注入
# CC_STATUSLINE_THEME は nix/home/default.nix の sessionVariables で flavor 連動
{inputs}: {
  cli-tools = _final: prev: let
    cliToolsPkgs = inputs.cli-tools.packages.${prev.stdenv.hostPlatform.system};
  in {
    inherit (cliToolsPkgs) cc-statusline daily memo;
  };
}
