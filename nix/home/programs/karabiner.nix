{
  pkgs,
  lib,
  config,
  validDotfilesDir,
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  # writeToProfile()は既存profileを上書きするため、未作成ならstubを置いてから生成する。
  # CIではdenoのローカルビルドを避けるため実行しない。
  home.activation.buildKarabinerConfig = lib.mkIf (isDarwin && !isCI) (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      KARABINER_DIR="${config.home.homeDirectory}/.config/karabiner"
      $DRY_RUN_CMD mkdir -p "$KARABINER_DIR"
      if [ ! -f "$KARABINER_DIR/karabiner.json" ]; then
        $DRY_RUN_CMD tee "$KARABINER_DIR/karabiner.json" > /dev/null <<< '{"global":{},"profiles":[{"name":"Default","selected":true}]}'
      fi
      $DRY_RUN_CMD ${pkgs.deno}/bin/deno run \
        --config "${validDotfilesDir}/karabiner-config/deno.json" \
        --allow-env --allow-read --allow-write \
        "${validDotfilesDir}/karabiner-config/karabiner.ts"
    ''
  );
}
