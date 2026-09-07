{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
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
      # 実ディレクトリが残っていると ln -sf はその中にリンクを作るため先に消す
      $DRY_RUN_CMD rm -rf "$target"
      $DRY_RUN_CMD ln -s "$browser" "$target"
    done
  '';
}
