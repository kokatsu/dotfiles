{config, ...}: let
  p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
  rgb = color: "${toString color.rgb.r},${toString color.rgb.g},${toString color.rgb.b}";
in {
  programs.ripgrep = {
    enable = true;
    # --sort は単一スレッドになるのでここでは指定しない。目視用の並び替えは rgs 関数で行う。
    arguments = [
      "--hidden"
      "--follow"
      "--no-ignore"
      "--glob=!.anyenv"
      "--glob=!.bun"
      "--glob=!.bundle"
      "--glob=!.cache"
      "--glob=!.cargo"
      "--glob=!.git"
      "--glob=!.vite"
      "--glob=!asset.*"
      "--glob=!debug"
      "--glob=!dist"
      "--glob=!node_modules"
      "--glob=!public"
      "--glob=!result"
      "--glob=!storybook-static"
      "--glob=!target"
      "--glob=!tmp"
      "--glob=!Trash"
      "--glob=!vendor"
      "--glob=!*.lock"
      "--glob=!*.log"
      "--glob=!package-lock.json"
      "--max-columns=10000"
      "--max-columns-preview"
      "--smart-case"
      "--colors=path:fg:${rgb p.blue}"
      "--colors=line:fg:${rgb p.green}"
      "--colors=match:bg:${rgb p.yellow}"
      "--colors=match:fg:${rgb p.base}"
      "--colors=match:style:nobold"
    ];
  };
}
