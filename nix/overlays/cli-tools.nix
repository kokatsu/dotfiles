# cli-tools flake の packages を dotfiles 側 pkgs に注入
# cc-statusline のみ CC_STATUSLINE_THEME を wrap (Catppuccin flavor 連動)
{inputs}: {
  cli-tools = _final: prev: let
    cliToolsPkgs = inputs.cli-tools.packages.${prev.system};
  in {
    inherit (cliToolsPkgs) cc-filter daily memo;
    cc-statusline =
      prev.runCommand "cc-statusline-wrapped" {
        nativeBuildInputs = [prev.makeWrapper];
      } ''
        mkdir -p $out/bin
        makeWrapper ${cliToolsPkgs.cc-statusline}/bin/cc-statusline \
          $out/bin/cc-statusline \
          --set-default CC_STATUSLINE_THEME catppuccin-mocha
      '';
  };
}
