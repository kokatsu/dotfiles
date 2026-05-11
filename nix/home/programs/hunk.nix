{inputs, ...}: {
  imports = [inputs.hunk.homeManagerModules.default];

  programs.hunk.enable = true;
}
