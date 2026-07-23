{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  # agent-browserがPLAYWRIGHT_BROWSERS_PATHを無視するため、既定cacheへリンクする。
  home.activation.setupPlaywrightBrowsers = lib.hm.dag.entryAfter ["linkGeneration"] ''
    PLAYWRIGHT_CACHE="${
      if isDarwin
      then "$HOME/Library/Caches/ms-playwright"
      else "$HOME/.cache/ms-playwright"
    }"
    PLAYWRIGHT_BROWSERS="${pkgs.playwright-driver.browsers}"
    $DRY_RUN_CMD mkdir -p "$PLAYWRIGHT_CACHE"
    for browser in "$PLAYWRIGHT_BROWSERS"/*; do
      name=$(basename "$browser")
      target="$PLAYWRIGHT_CACHE/$name"
      if [ -L "$target" ]; then
        $DRY_RUN_CMD rm "$target"
      fi
      $DRY_RUN_CMD ln -sf "$browser" "$target"
    done
  '';
}
