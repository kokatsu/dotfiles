{config, ...}: let
  # Claude Code カスタムテーマ (2.1.118+): 4 flavor (latte/frappe/macchiato/mocha) を
  # ~/.config/claude/themes/ に生成。`/theme` で "Catppuccin <Flavor>" を選択。
  # 注: diff 描画は起動時のテーマを握ったままで、switch してもファイルウォッチでは
  #     反映されない (2.1.246 で実測)。色を変えたら Claude Code の再起動が必要。
  mkClaudeTheme = flavor: let
    p = config.catppuccinLib.palettes.${flavor};
    names = config.catppuccinLib.flavorNames flavor;
    themeBase =
      if flavor == "latte"
      then "light"
      else "dark";
    # ratio は 0-100 (foreground の比率)
    # Claude Code は `rgb(r,g,b)` / `#rrggbb` / `ansi256(n)` / `ansi:<name>` を受理する
    # diff 系は行背景・単語背景ともに override が効く (2.1.246 で修正)
    # diffAddedWord/diffRemovedWord は前景色ではなく変更単語の「背景色」。
    #
    # 行背景は GUI (デスクトップアプリ) の Catppuccin コードテーマの実測値 (dark 18 / light 11)。
    blend = fg: bg: ratio: let
      mix = a: b: (a * ratio + b * (100 - ratio)) / 100;
    in "rgb(${toString (mix fg.rgb.r bg.rgb.r)},${toString (mix fg.rgb.g bg.rgb.g)},${toString (mix fg.rgb.b bg.rgb.b)})";
    diffRatio =
      if themeBase == "light"
      then {
        line = 11;
        dim = 6;
      }
      else {
        line = 18;
        dim = 10;
      };
    # dark の単語背景は base ブレンドを使わない。ブレンドは彩度を 10% 前後まで
    # 落として灰色に寄せるため、単語帯の文字と分離せず「白地に白文字」に見える。
    # なお単語帯の文字色はシンタックスハイライタ側の #f8f8f2 固定で、
    # custom theme の text は効かない (実測)。コントラストはこの値を基準に見る。
    # 灰色から遠ざけて彩度を上げ (satK)、その後まとめて暗くする (lightScale)。
    # 千分率の整数で扱い、Nix の整数除算だけで完結させる。
    vivid = fg: satK: lightScale: let
      r = fg.rgb.r;
      g = fg.rgb.g;
      b = fg.rgb.b;
      mx =
        if r >= g && r >= b
        then r
        else if g >= b
        then g
        else b;
      mn =
        if r <= g && r <= b
        then r
        else if g <= b
        then g
        else b;
      mid = (mx + mn) / 2;
      ch = c: let
        v = (mid * 1000 + (c - mid) * satK) * lightScale / 1000000;
      in
        if v < 0
        then 0
        else if v > 255
        then 255
        else v;
    in "rgb(${toString (ch r)},${toString (ch g)},${toString (ch b)})";
    # light は前景が暗い文字なので、明るい単語背景でも読める。ブレンドのままでよい。
    diffWord = fg:
      if themeBase == "light"
      then blend fg p.base 25
      else vivid fg 2000 360;
  in
    builtins.toJSON {
      name = names.spaced;
      base = themeBase;
      overrides = {
        diffAdded = blend p.green p.base diffRatio.line;
        diffRemoved = blend p.red p.base diffRatio.line;
        diffAddedDimmed = blend p.green p.base diffRatio.dim;
        diffRemovedDimmed = blend p.red p.base diffRatio.dim;

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

        diffAddedWord = diffWord p.green;
        diffRemovedWord = diffWord p.red;

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
