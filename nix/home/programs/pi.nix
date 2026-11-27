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
  settings = {
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
    "extensions/fff".source = pkgs.pi-fff;

    # herdr-peer は Claude と Codex の組を前提にするので共有しない。
    "skills/browser-research".source = ../../../.config/claude/skills/browser-research;
    "skills/japanese-writing".source = ../../../.config/claude/skills/japanese-writing;
  };
  hostPiDir = "${config.xdg.configHome}/pi";
  nonoPiDir = "${config.xdg.dataHome}/nono-agent/pi";
  resourcePaths = kind:
    map (name: "${hostPiDir}/${name}")
    (builtins.filter (lib.hasPrefix "${kind}/") (builtins.attrNames files));
  json = pkgs.formats.json {};
  baseSettings = json.generate "pi-settings.json" settings;
  nonoSettings = json.generate "nono-pi-settings.json" (settings
    // {
      extensions = resourcePaths "extensions";
      skills = resourcePaths "skills";
      themes = resourcePaths "themes";
    });
  # nono-agent は会話やログイン情報を分けるため、専用の PI_CODING_AGENT_DIR を使う
  piDirs =
    [hostPiDir] ++ lib.optionals (!isDevcontainer) [nonoPiDir];
in {
  home = {
    file = lib.mapAttrs' (name: lib.nameValuePair "${hostPiDir}/${name}") files;

    # pi は settings.json に lastChangelogVersion や /settings の変更を書き戻すので、
    # store への symlink にはできない。ここで決めたキーだけを上書きし、残りは保つ。
    activation.mergePiSettings =
      lib.hm.dag.entryAfter ["linkGeneration"]
      # bash
      ''
        for PI_DIR in ${lib.concatMapStringsSep " " lib.escapeShellArg piDirs}; do (
          BASE="${baseSettings}"
          if [ "$PI_DIR" = ${lib.escapeShellArg nonoPiDir} ]; then
            BASE="${nonoSettings}"
          fi
          if [ -n "$DRY_RUN_CMD" ]; then
            echo "Merging managed keys into $PI_DIR/settings.json"
            exit 0
          fi
          mkdir -p "$PI_DIR"
          cd -P -- "$PI_DIR"
          if [ "$PI_DIR" = ${lib.escapeShellArg nonoPiDir} ] && [ "$PWD" != "$(cd -P -- "$(dirname "$PI_DIR")" && pwd)/pi" ]; then
            echo "Unexpected nono Pi directory: $PWD" >&2
            exit 1
          fi
          TARGET=settings.json
          # nono-agent の中の pi は PI_DIR に書け、ここと並行して中身を差し替えられる。
          # 一時ファイルは書けない親に作り、settings.json は O_NOFOLLOW で一度だけ開き、
          # mv -T で symlink を辿らずに置き換える。ハードリンクは Landlock が EXDEV で拒否する
          TMP=$(${pkgs.coreutils}/bin/mktemp "$(dirname "$PI_DIR")/.pi-settings.json.XXXXXX")
          # 中の pi が壊した内容で switch 全体を止めないよう、読めないときは警告して残す。
          # resource 配列では ${hostPiDir}/<kind>/ 以下を HM の管理分とみなし、BASE に無いものは外す
          if [ -L "$TARGET" ] || [ ! -f "$TARGET" ]; then
            cat "$BASE" > "$TMP"
          elif ! (set -o pipefail
            ${pkgs.coreutils}/bin/dd if="$TARGET" iflag=nofollow,nonblock status=none \
              | ${lib.getExe pkgs.jq} -n --slurpfile base "$BASE" --arg host ${lib.escapeShellArg hostPiDir} --arg home ${lib.escapeShellArg config.home.homeDirectory} '
                  [inputs] as $docs
                  | if $docs == [] then {}
                    elif ($docs | length) == 1 and ($docs[0] | type) == "object" then $docs[0]
                    else error("expected a single JSON object") end
                  | . as $user
                  | $base[0] as $base
                  | reduce ($base | to_entries[] | select(.key | IN("extensions", "skills", "themes"))) as {key: $key, value: $paths} ($user * $base;
                      .[$key] = [($user[$key] // [])[] | select(sub("^~/"; "\($home)/") | startswith("\($host)/\($key)/") | not)] + $paths)
                ' > "$TMP"); then
            rm -f "$TMP"
            warnEcho "Skipped merging Pi settings: $PI_DIR/settings.json is not a single JSON object"
            exit 0
          fi
          chmod 644 "$TMP"
          ${pkgs.coreutils}/bin/mv -fT "$TMP" "$TARGET" \
            || { rm -f "$TMP"; warnEcho "Could not replace $PI_DIR/settings.json"; }
          if [ "$PI_DIR" = ${lib.escapeShellArg nonoPiDir} ]; then
            TMP=$(${pkgs.coreutils}/bin/mktemp "$(dirname "$PI_DIR")/.pi-agents.md.XXXXXX")
            ${pkgs.coreutils}/bin/install -m 644 "${files."AGENTS.md".source}" "$TMP"
            ${pkgs.coreutils}/bin/mv -fT "$TMP" AGENTS.md \
              || { rm -f "$TMP"; warnEcho "Could not replace $PI_DIR/AGENTS.md"; }
          fi
        ); done
      '';
  };
}
