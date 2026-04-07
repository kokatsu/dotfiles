let
  lib = import ./lib.nix;
  inherit (lib) mkBinaryRelease;
in {
  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = mkBinaryRelease rec {
    pname = "claude-code";
    version = "2.1.94";
    hashes = {
      "aarch64-darwin" = "sha256-bRuWV3J9zoEzKzzaEb/gqMg+I5LjwGKjECLhCw5xzdE=";
      "x86_64-darwin" = "sha256-1CK1zJdLO8Syj2mBRP0DFvPhd3S6vgvB63bCuwhY0Ko=";
      "aarch64-linux" = "sha256-CN6z1WR3SW65LmJPSS4lsSP0Un3VZ09xr/9YpI7M2VM=";
      "x86_64-linux" = "sha256-4iMkUUln/y1en5Hw7jfkZ1v4tt/sJ/r7GcslzFsj/K8=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    url = platform: "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude";
    binName = "claude";
    meta = {
      description = "Claude Code - an agentic coding tool";
      homepage = "https://github.com/anthropics/claude-code";
      license = "unfree";
    };
  };

  # Add termframe package (not in nixpkgs)
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=pamburus/termframe
  termframe = mkBinaryRelease rec {
    pname = "termframe";
    version = "0.8.3";
    hashes = {
      "aarch64-darwin" = "sha256-/VIuBBdH+MDTRkFoy/0a1kmFWyIuEBGp9RNnU26YkXU=";
      "x86_64-darwin" = "sha256-O4CGEP3IC8qhY9o9XyEee/wQE25eykUcaxyaSnNwkUs=";
      "aarch64-linux" = "sha256-ErOVyg4HXTAjHIBYs13h5Fn3EJGiMZBKLvjXMTFC83I=";
      "x86_64-linux" = "sha256-XGN10FwEEk06wtydfUvAXlccONtHxb+3A5PbIpongjw=";
    };
    platformMap = {
      "aarch64-darwin" = "macos-arm64";
      "x86_64-darwin" = "macos-x86_64";
      "aarch64-linux" = "linux-arm64-gnu";
      "x86_64-linux" = "linux-x86_64-gnu";
    };
    url = platform: "https://github.com/pamburus/termframe/releases/download/v${version}/termframe-${platform}.tar.gz";
    format = "tar";
    extraAttrs = {sourceRoot = ".";};
    meta = {
      description = "Terminal output SVG screenshot tool";
      homepage = "https://github.com/pamburus/termframe";
    };
  };

  # kakehashi - Tree-sitter Language Server
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=atusy/kakehashi
  kakehashi = mkBinaryRelease rec {
    pname = "kakehashi";
    version = "0.4.1";
    hashes = {
      "aarch64-darwin" = "sha256-nvWXxqsWoX6NsULa0qSx7TFeMlgid5hd4/keK0wGEtk=";
      "x86_64-darwin" = "sha256-iFwXleFxBDO6hRUUZldk0JR/1PRmEZhZ4yBZ6qemtHc=";
      "aarch64-linux" = "sha256-mEe90L7/P2TphiEbvcFw8qRVjeLLLikADJCdbPKFHIk=";
      "x86_64-linux" = "sha256-DFSVXRLBZ4qvNYzItnu9t2K3KxK9D2Jpppz0gae2vRo=";
    };
    platformMap = {
      "aarch64-darwin" = "aarch64-apple-darwin";
      "x86_64-darwin" = "x86_64-apple-darwin";
      "aarch64-linux" = "aarch64-unknown-linux-gnu";
      "x86_64-linux" = "x86_64-unknown-linux-gnu";
    };
    url = platform: "https://github.com/atusy/kakehashi/releases/download/v${version}/kakehashi-v${version}-${platform}.tar.gz";
    format = "tar";
    extraAttrs = {sourceRoot = ".";};
    meta = {
      description = "Tree-sitter Language Server for embedded languages";
      homepage = "https://github.com/atusy/kakehashi";
    };
  };

  # octorus - TUI tool for GitHub PR review
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=ushironoko/octorus
  octorus = mkBinaryRelease rec {
    pname = "octorus";
    version = "0.6.1";
    hashes = {
      "aarch64-darwin" = "sha256-AWvcVFARwiDOVYyhSP1/4CNIkRmtRkI1j0Hj/UYvGYk=";
      "x86_64-darwin" = "sha256-7wws8I1XjubwQ1H3YYXzYS9zb00TRVhuQkEaJzAMGtk=";
      "aarch64-linux" = "sha256-iF6Eo/yRrsCs80OQBDvZwPry0POJ0Y/sGcpmyOqY8Uw=";
      "x86_64-linux" = "sha256-Yf64ijzZx+v/voM04Qv/bSwxf0RGcizec41xiQCFl0U=";
    };
    platformMap = {
      "aarch64-darwin" = "aarch64-apple-darwin";
      "x86_64-darwin" = "x86_64-apple-darwin";
      "aarch64-linux" = "aarch64-unknown-linux-gnu";
      "x86_64-linux" = "x86_64-unknown-linux-gnu";
    };
    url = platform: "https://github.com/ushironoko/octorus/releases/download/v${version}/octorus-${version}-${platform}.tar.gz";
    format = "tar";
    binName = "or";
    meta = {
      description = "TUI tool for GitHub PR review with Vim-style keybindings";
      homepage = "https://github.com/ushironoko/octorus";
    };
  };
}
