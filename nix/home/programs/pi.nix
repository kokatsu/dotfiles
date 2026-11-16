{
  pkgs,
  lib,
  config,
  ...
}: let
  flavor = config.catppuccin.flavor;
  themeName = (config.catppuccinLib.flavorNames flavor).kebab;
  p = config.catppuccinLib.palettes.${flavor};
  tint = color: (config.catppuccinLib.blend p.${color} p.base (config.catppuccinLib.diffRatio flavor).line).hex;
  theme = {
    "$schema" = "https://pi.dev/schemas/theme.schema.json";
    name = themeName;
    appearance =
      if flavor == "latte"
      then "light"
      else "dark";
    vars = builtins.mapAttrs (_: color: color.hex) p;
    colors = {
      accent = config.catppuccin.accent;
      border = "overlay0";
      borderAccent = config.catppuccin.accent;
      borderMuted = "surface1";
      success = "green";
      error = "red";
      warning = "yellow";
      muted = "subtext0";
      dim = "overlay1";
      text = "text";
      thinkingText = "subtext0";
      scrollbarTrack = "surface1";
      scrollbarThumb = "overlay2";
      selectedBg = "surface1";
      searchMatchBg = "yellow";
      searchMatchText = "base";
      userMessageBg = "surface0";
      userMessageText = "text";
      customMessageBg = "mantle";
      customMessageText = "text";
      customMessageLabel = "mauve";
      toolPendingBg = "mantle";
      toolSuccessBg = tint "green";
      toolErrorBg = tint "red";
      toolTitle = config.catppuccin.accent;
      toolOutput = "text";
      mdHeading = "mauve";
      mdLink = "blue";
      mdLinkUrl = "subtext0";
      mdCode = "peach";
      mdCodeBlock = "text";
      mdCodeBlockBorder = "overlay0";
      mdQuote = "subtext1";
      mdQuoteBorder = "surface2";
      mdHr = "surface2";
      mdListBullet = "teal";
      toolDiffAdded = "green";
      toolDiffRemoved = "red";
      toolDiffContext = "subtext0";
      syntaxComment = "overlay2";
      syntaxKeyword = "mauve";
      syntaxFunction = "blue";
      syntaxVariable = "text";
      syntaxString = "green";
      syntaxNumber = "peach";
      syntaxType = "yellow";
      syntaxOperator = "sky";
      syntaxPunctuation = "overlay2";
      thinkingOff = "overlay0";
      thinkingMinimal = "subtext0";
      thinkingLow = "blue";
      thinkingMedium = "teal";
      thinkingHigh = "mauve";
      thinkingXhigh = "pink";
      thinkingMax = "red";
      bashMode = "peach";
    };
    export = {
      pageBg = "base";
      cardBg = "mantle";
      infoBg = "surface0";
    };
  };
  # Pi imports an extension from its symlink target, so a relative import such
  # as ai-writing.ts → ./agent-guard.ts resolves only when every file comes
  # from the same store directory.
  extensions = ../../../.config/pi/extensions;
  baseSettings = (pkgs.formats.json {}).generate "pi-settings.json" {
    "$schema" = "https://pi.dev/schemas/settings.schema.json";
    collapseChangelog = true;
    defaultModel = "gpt-6.1-sol";
    defaultProvider = "openai-codex";
    defaultTools = ["+grep" "+find" "+ls"];
    editorPaddingX = 1;
    showHardwareCursor = true;
    theme = themeName;
  };
in {
  home = {
    file = {
      ".config/pi/themes/${themeName}.json".text = builtins.toJSON theme;
      ".config/pi/AGENTS.md".source = ../../../.config/pi/.AGENTS.md;
      ".config/pi/extensions/agent-guard.ts".source = "${extensions}/agent-guard.ts";
      ".config/pi/extensions/ai-writing.ts".source = "${extensions}/ai-writing.ts";
      ".config/pi/extensions/statusline.ts".source = "${extensions}/statusline.ts";

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
