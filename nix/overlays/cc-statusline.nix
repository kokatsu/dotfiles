# cc-statusline flake の package を dotfiles 側 pkgs に注入
# CC_STATUSLINE_THEME は nix/home/default.nix の sessionVariables で flavor 連動
{inputs}: {
  cc-statusline = _final: prev: let
    ccStatuslinePkgs = inputs.cc-statusline.packages.${prev.stdenv.hostPlatform.system};
  in {
    inherit (ccStatuslinePkgs) cc-statusline;
  };
}
