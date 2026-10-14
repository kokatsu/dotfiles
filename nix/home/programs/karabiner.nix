{
  pkgs,
  lib,
  config,
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in {
  home.activation.buildKarabinerConfig = lib.mkIf (isDarwin && !isCI) (
    lib.hm.dag.entryAfter ["writeBoundary"]
    # bash
    ''
      $DRY_RUN_CMD ${pkgs.writeShellApplication {
        name = "apply-karabiner-profile";
        runtimeInputs = [pkgs.jq pkgs.coreutils];
        text = builtins.readFile ../../../scripts/apply-karabiner-profile.sh;
      }}/bin/apply-karabiner-profile \
        ${pkgs.karabiner-config}/profile.json \
        "${config.xdg.configHome}/karabiner/karabiner.json"
    ''
  );
}
