{
  pkgs,
  lib,
  config,
  isDevcontainer,
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
    defaultModel = "gpt-6.2-sol";
    defaultThinkingLevel = "medium";
    defaultProvider = "openai-codex";
    defaultTools = ["+grep" "+find" "+ls"];
    editorPaddingX = 1;
    showHardwareCursor = true;
    theme = themeName;
  };
  files = {
    "themes/${themeName}.json".text = builtins.toJSON theme;
    "AGENTS.md".source = ../../../.config/pi/.AGENTS.md;
    "extensions/agent-guard.ts".source = "${extensions}/agent-guard.ts";
    "extensions/ai-writing.ts".source = "${extensions}/ai-writing.ts";
    "extensions/statusline.ts".source = "${extensions}/statusline.ts";

    # herdr-peer は Claude と Codex の組を前提にするので共有しない。
    "skills/browser-research".source = ../../../.config/claude/skills/browser-research;
    "skills/japanese-writing".source = ../../../.config/claude/skills/japanese-writing;
  };
  # nono-agent は会話やログイン情報を分けるため、専用の PI_CODING_AGENT_DIR を使う
  piDirs =
    ["${config.xdg.configHome}/pi"]
    ++ lib.optionals (!isDevcontainer) ["${config.xdg.dataHome}/nono-agent/pi"];
in {
  home = {
    file = lib.mergeAttrsList (map (dir: lib.mapAttrs' (name: lib.nameValuePair "${dir}/${name}") files) piDirs);

    # pi は settings.json に lastChangelogVersion や /settings の変更を書き戻すので、
    # store への symlink にはできない。ここで決めたキーだけを上書きし、残りは保つ。
    activation.mergePiSettings =
      lib.hm.dag.entryAfter ["linkGeneration"]
      # bash
      ''
        BASE="${baseSettings}"
        for PI_DIR in ${lib.concatMapStringsSep " " lib.escapeShellArg piDirs}; do
          TARGET="$PI_DIR/settings.json"
          if [ -n "$DRY_RUN_CMD" ]; then
            echo "Merging managed keys into $TARGET"
            continue
          fi
          mkdir -p "$PI_DIR"
          # nono-agent の中の pi は PI_DIR に書け、ここと並行して中身を差し替えられる。
          # 一時ファイルは書けない親に作り、settings.json は O_NOFOLLOW で一度だけ開き、
          # mv -T で symlink を辿らずに置き換える。ハードリンクは Landlock が EXDEV で拒否する
          TMP=$(${pkgs.coreutils}/bin/mktemp "$(dirname "$PI_DIR")/.pi-settings.json.XXXXXX")
          if [ -L "$TARGET" ] || [ ! -f "$TARGET" ]; then
            cat "$BASE" > "$TMP"
          else
            (set -o pipefail
              ${pkgs.coreutils}/bin/dd if="$TARGET" iflag=nofollow,nonblock status=none \
                | ${lib.getExe pkgs.jq} -s '.[0] * .[1]' - "$BASE") > "$TMP" \
              || { rm -f "$TMP"; exit 1; }
          fi
          chmod 644 "$TMP"
          ${pkgs.coreutils}/bin/mv -fT "$TMP" "$TARGET"
        done
      '';
  };
}
