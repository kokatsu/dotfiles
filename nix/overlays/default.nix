let
  binaryReleases = import ./binary-releases.nix;
  npmPackages = import ./npm-packages.nix;
  buildFixes = import ./build-fixes.nix;
  sourceBuilds = import ./source-builds.nix;
  standalone = import ./standalone.nix;
in
  binaryReleases // npmPackages // buildFixes // sourceBuilds // standalone
