{config, ...}: let
  # Claude Code カスタムテーマ (2.1.118+): 4 flavor (latte/frappe/macchiato/mocha) を
  # ~/.config/claude/themes/ に生成。起動中もファイルウォッチで反映。
  # `/theme` で "Catppuccin <Flavor>" を選択
  mkClaudeTheme = flavor: let
    p = config.catppuccinLib.palettes.${flavor};
    names = config.catppuccinLib.flavorNames flavor;
    themeBase =
      if flavor == "latte"
      then "light"
      else "dark";
    # ratio は 0-100 (foreground の比率)
    # Claude Code は `rgb(r,g,b)` / `#rrggbb` / `ansi256(n)` / `ansi:<name>` を受理する
    # 注: 2.1.118 時点で diffAdded/diffRemoved(Dimmed) の背景色は override されず
    #     base defaults が使われるバグがある。ここの値は将来修正された時用
    blend = fg: bg: ratio: let
      mix = a: b: (a * ratio + b * (100 - ratio)) / 100;
    in "rgb(${toString (mix fg.rgb.r bg.rgb.r)},${toString (mix fg.rgb.g bg.rgb.g)},${toString (mix fg.rgb.b bg.rgb.b)})";
  in
    builtins.toJSON {
      name = names.spaced;
      base = themeBase;
      overrides = {
        diffAdded = blend p.green p.base 18;
        diffRemoved = blend p.red p.base 18;
        diffAddedDimmed = blend p.green p.base 10;
        diffRemovedDimmed = blend p.red p.base 10;

        text = p.text.hex;
        inverseText = p.base.hex;
        inactive = p.overlay1.hex;
        inactiveShimmer = p.overlay2.hex;
        subtle = p.surface1.hex;

        claude = p.peach.hex;
        claudeShimmer = p.flamingo.hex;
        claudeBlue_FOR_SYSTEM_SPINNER = p.lavender.hex;
        claudeBlueShimmer_FOR_SYSTEM_SPINNER = p.sky.hex;

        autoAccept = p.mauve.hex;
        permission = p.lavender.hex;
        permissionShimmer = p.sky.hex;
        suggestion = p.lavender.hex;
        remember = p.lavender.hex;
        merged = p.mauve.hex;

        bashBorder = p.pink.hex;
        promptBorder = p.overlay0.hex;
        promptBorderShimmer = p.overlay1.hex;

        planMode = p.teal.hex;
        ide = p.sapphire.hex;
        fastMode = p.peach.hex;
        fastModeShimmer = p.flamingo.hex;

        success = p.green.hex;
        error = p.red.hex;
        warning = p.yellow.hex;
        warningShimmer = p.yellow.hex;

        diffAddedWord = p.green.hex;
        diffRemovedWord = p.maroon.hex;

        userMessageBackground = p.surface0.hex;
        userMessageBackgroundHover = p.surface1.hex;
        messageActionsBackground = p.mantle.hex;
        selectionBg = p.surface1.hex;
        bashMessageBackgroundColor = p.surface0.hex;
        memoryBackgroundColor = p.surface0.hex;

        red_FOR_SUBAGENTS_ONLY = p.red.hex;
        blue_FOR_SUBAGENTS_ONLY = p.blue.hex;
        green_FOR_SUBAGENTS_ONLY = p.green.hex;
        yellow_FOR_SUBAGENTS_ONLY = p.yellow.hex;
        purple_FOR_SUBAGENTS_ONLY = p.mauve.hex;
        orange_FOR_SUBAGENTS_ONLY = p.peach.hex;
        pink_FOR_SUBAGENTS_ONLY = p.pink.hex;
        cyan_FOR_SUBAGENTS_ONLY = p.sky.hex;

        briefLabelYou = p.sapphire.hex;
        briefLabelClaude = p.peach.hex;

        rate_limit_fill = p.lavender.hex;
        rate_limit_empty = p.surface1.hex;

        rainbow_red = p.red.hex;
        rainbow_orange = p.peach.hex;
        rainbow_yellow = p.yellow.hex;
        rainbow_green = p.green.hex;
        rainbow_blue = p.blue.hex;
        rainbow_indigo = p.lavender.hex;
        rainbow_violet = p.mauve.hex;

        rainbow_red_shimmer = p.maroon.hex;
        rainbow_orange_shimmer = p.flamingo.hex;
        rainbow_yellow_shimmer = p.yellow.hex;
        rainbow_green_shimmer = p.teal.hex;
        rainbow_blue_shimmer = p.sapphire.hex;
        rainbow_indigo_shimmer = p.lavender.hex;
        rainbow_violet_shimmer = p.pink.hex;
      };
    };
in {
  home.file = builtins.listToAttrs (map (flavor: {
    name = ".config/claude/themes/catppuccin-${flavor}.json";
    value = {text = mkClaudeTheme flavor;};
  }) ["latte" "frappe" "macchiato" "mocha"]);
}
