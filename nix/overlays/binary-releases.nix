let
  lib = import ./lib.nix;
  inherit (lib) mkBinaryRelease;
in {
  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = mkBinaryRelease rec {
    pname = "claude-code";
    version = "2.1.85";
    hashes = {
      "aarch64-darwin" = "sha256-wC2RH/E/jOzLH2ZivyEfPNnynVpG8DHDzEBlTrdZqik=";
      "x86_64-darwin" = "sha256-2l7S7hsLz2XCCI55vGU4jshe3EEEH8bKfCczDy4gEIU=";
      "aarch64-linux" = "sha256-XIaBdLREOeUcdP8ITDBoVsQXeWFSUNW72qXRAFY2KBQ=";
      "x86_64-linux" = "sha256-xocqqNuU8wO8akSCZk5A0yiN/JicibomhHPtMuMFWHg=";
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
    version = "0.5.8";
    hashes = {
      "aarch64-darwin" = "sha256-+2NnSehxPVO8xJgcZgvyAGbGtNOu+QSjHgpbJT8oxys=";
      "x86_64-darwin" = "sha256-dcZqsa0ngvLcTnc4Slf7zEM8aVnf+wX/vYYBwT+xTMg=";
      "aarch64-linux" = "sha256-Nj4RbYdgCe7SWU+WJziMEXW2VAxxczPN2ljypJysht4=";
      "x86_64-linux" = "sha256-jSM62QZgbBPIxzKuAVcgmHfaLPSJAC/0X1+xFQALfRE=";
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
