{inputs}: let
  binaryReleases = import ./binary-releases.nix;
  npmPackages = import ./npm-packages.nix;
  buildFixes = import ./build-fixes.nix;
  sourceBuilds = import ./source-builds.nix;
  ccStatusline = import ./cc-statusline.nix {inherit inputs;};
  agentHooks = import ./agent-hooks.nix;
  herdr = import ./herdr.nix {inherit inputs;};
  unocssLanguageServer = import ./unocss-language-server.nix {inherit inputs;};
in
  binaryReleases // npmPackages // buildFixes // sourceBuilds // ccStatusline // agentHooks // herdr // unocssLanguageServer
