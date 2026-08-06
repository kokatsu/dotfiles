{inputs}: let
  binaryReleases = import ./binary-releases.nix;
  npmPackages = import ./npm-packages.nix;
  buildFixes = import ./build-fixes.nix;
  sourceBuilds = import ./source-builds.nix;
  standalone = import ./standalone.nix;
  ccStatusline = import ./cc-statusline.nix {inherit inputs;};
  herdr = import ./herdr.nix {inherit inputs;};
  hermesAgent = import ./hermes-agent.nix {inherit inputs;};
  unocssLanguageServer = import ./unocss-language-server.nix {inherit inputs;};
in
  binaryReleases // npmPackages // buildFixes // sourceBuilds // standalone // ccStatusline // herdr // hermesAgent // unocssLanguageServer
