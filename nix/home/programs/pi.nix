{
  pkgs,
  lib,
  config,
  ...
}: let
  baseSettings = (pkgs.formats.json {}).generate "pi-settings.json" {
    "$schema" = "https://pi.dev/schemas/settings.schema.json";
    collapseChangelog = true;
    defaultModel = "gpt-6.1-sol";
    defaultProvider = "openai-codex";
  };
in {
  home = {
    file = {
      ".config/pi/AGENTS.md".source = ../../../.config/pi/.AGENTS.md;
      ".config/pi/extensions/agent-guard.ts".source = ../../../.config/pi/extensions/agent-guard.ts;
      ".config/pi/extensions/statusline.ts".source = ../../../.config/pi/extensions/statusline.ts;

      # herdr-peer は Claude と Codex の組を前提にするので共有しない。
      ".config/pi/skills/browser-research".source = ../../../.config/claude/skills/browser-research;
      ".config/pi/skills/japanese-writing".source = ../../../.config/claude/skills/japanese-writing;
    };

    # pi は settings.json に lastChangelogVersion や /settings の変更を書き戻すので、
    # store への symlink にはできない。ここで決めたキーだけを上書きし、残りは保つ。
    activation.mergePiSettings =
      lib.hm.dag.entryAfter ["linkGeneration"]
      # bash
      ''
        PI_DIR="${config.xdg.configHome}/pi"
        BASE="${baseSettings}"
        TARGET="$PI_DIR/settings.json"
        $DRY_RUN_CMD mkdir -p "$PI_DIR"
        if [ ! -f "$TARGET" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 "$BASE" "$TARGET"
        elif [ -n "$DRY_RUN_CMD" ]; then
          echo "Merging managed keys into $TARGET"
        else
          MERGED=$(${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$TARGET" "$BASE")
          printf '%s\n' "$MERGED" > "$TARGET.tmp"
          ${pkgs.coreutils}/bin/mv -f "$TARGET.tmp" "$TARGET"
        fi
      '';
  };
}
