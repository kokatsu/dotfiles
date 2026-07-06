{config, ...}: let
  # Hermes Agent カスタムスキン: 4 flavor を生成
  # YAML は JSON のスーパーセットなので builtins.toJSON 出力をそのまま .yaml として読ませる
  mkHermesSkin = flavor: let
    p = config.catppuccinLib.palettes.${flavor};
    names = config.catppuccinLib.flavorNames flavor;
  in
    builtins.toJSON {
      name = "catppuccin-${flavor}";
      description = "Catppuccin ${names.capitalized} for Hermes Agent";
      colors = {
        banner_border = p.mauve.hex;
        banner_title = p.yellow.hex;
        banner_accent = p.teal.hex;
        banner_dim = p.overlay1.hex;
        banner_text = p.text.hex;
        ui_accent = p.mauve.hex;
        ui_label = p.sapphire.hex;
        ui_ok = p.green.hex;
        ui_error = p.red.hex;
        ui_warn = p.peach.hex;
        prompt = p.text.hex;
        input_rule = p.surface1.hex;
        response_border = p.mauve.hex;
        status_bar_bg = p.mantle.hex;
        status_bar_text = p.subtext1.hex;
        status_bar_strong = p.yellow.hex;
        status_bar_dim = p.overlay0.hex;
        status_bar_good = p.green.hex;
        status_bar_warn = p.yellow.hex;
        status_bar_bad = p.peach.hex;
        status_bar_critical = p.red.hex;
        session_label = p.sapphire.hex;
        session_border = p.overlay0.hex;
        voice_status_bg = p.mantle.hex;
        selection_bg = p.surface1.hex;
        completion_menu_bg = p.mantle.hex;
        completion_menu_current_bg = p.surface1.hex;
        completion_menu_meta_bg = p.mantle.hex;
        completion_menu_meta_current_bg = p.surface1.hex;
      };
    };
in {
  home.file = builtins.listToAttrs (map (flavor: {
    name = ".config/hermes/skins/catppuccin-${flavor}.yaml";
    value = {text = mkHermesSkin flavor;};
  }) ["latte" "frappe" "macchiato" "mocha"]);
}
