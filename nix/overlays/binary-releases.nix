let
  lib = import ./lib.nix;
  inherit (lib) mkBinaryRelease;
in {
  # marksman - Markdown LSP (binary release)
  # nixpkgs の marksman は .NET 依存で Swift ビルド失敗するため GitHub バイナリを使用
  # Renovate: datasource=github-releases depName=artempyanykh/marksman
  marksman-binary = mkBinaryRelease rec {
    pname = "marksman";
    version = "2025-12-13";
    hashes = {
      "aarch64-darwin" = "sha256-7JSfQwwYZ5BXmDvNiiT5VVDt6iqFX8BAswfaZ8ePCYk=";
      "x86_64-darwin" = "sha256-7JSfQwwYZ5BXmDvNiiT5VVDt6iqFX8BAswfaZ8ePCYk=";
      "aarch64-linux" = "sha256-X8vETHw2brLD8LcnDX2RKrofnCaod1sz7X0ydMUrOqA=";
      "x86_64-linux" = "sha256-1K9buN6h620jWhK3UTZW21FotG1AfSbnDl9o6RQ84G0=";
    };
    platformMap = {
      "aarch64-darwin" = "macos";
      "x86_64-darwin" = "macos";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    url = platform: "https://github.com/artempyanykh/marksman/releases/download/${version}/marksman-${platform}";
    meta = {
      description = "Markdown LSP server";
      homepage = "https://github.com/artempyanykh/marksman";
    };
  };

  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = mkBinaryRelease rec {
    pname = "claude-code";
    version = "2.1.72";
    hashes = {
      "aarch64-darwin" = "sha256-xYT1E2LVYmlbxxdQ0cIZb5oODjb9BD4rxoPM/Jo6s9c=";
      "x86_64-darwin" = "sha256-JLn6GD5CJmQPCiFY53cCsN2GDZIFsb7H5pVgmjCciYY=";
      "aarch64-linux" = "sha256-nwwQy50iLq9OxIcEA6FWGxMp3GaTA2Ezaah3/QWhFwg=";
      "x86_64-linux" = "sha256-tVM45/u4v30mi5G6s7KHU2Idq5Y3scypQ2afRJDth40=";
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
    version = "0.8.2";
    hashes = {
      "aarch64-darwin" = "sha256-Xr9n8FszlTW1IsPqtem77bxykka9e71hhnQbbvSo4w4=";
      "x86_64-darwin" = "sha256-4kLXVW1ebi6vlyGUpgHrvkt4uEXyUWmQgSJ8DAORSzI=";
      "aarch64-linux" = "sha256-dvUoWd3HoVor2CVigIWAJcL4DeSXH8vM4M7dSOiAHck=";
      "x86_64-linux" = "sha256-7ntrcjO0mNkC42TY742hcL119PV6ON6ENvkdtdEF3AI=";
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

  # keifu - Git commit graph TUI visualizer
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=trasta298/keifu
  keifu = mkBinaryRelease rec {
    pname = "keifu";
    version = "0.2.3";
    hashes = {
      "aarch64-darwin" = "sha256-EhaebJ1yXnm1vBPKKIrFveIbH9aSSTpdoEBKQHHI6yo=";
      "x86_64-darwin" = "sha256-bxXfILwGQgumxfFsCd6P9hFVFkjrSGA38Uq0bjnGOHM=";
      "aarch64-linux" = "sha256-67lAAzIUHNI7LFNX2QQX2msWACJA65AjIk5M/gL5B44=";
      "x86_64-linux" = "sha256-xt8COXNMFAu3kcd8dbqwNNN8DdFDjTx3IHP0CXNFpdk=";
    };
    platformMap = {
      "aarch64-darwin" = "aarch64-apple-darwin";
      "x86_64-darwin" = "x86_64-apple-darwin";
      "aarch64-linux" = "aarch64-unknown-linux-gnu";
      "x86_64-linux" = "x86_64-unknown-linux-gnu";
    };
    url = platform: "https://github.com/trasta298/keifu/releases/download/v${version}/keifu-v${version}-${platform}.tar.gz";
    format = "tar";
    extraAttrs = {sourceRoot = ".";};
    meta = {
      description = "Git commit graph TUI visualizer";
      homepage = "https://github.com/trasta298/keifu";
    };
  };

  # kakehashi - Tree-sitter Language Server
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=atusy/kakehashi
  kakehashi = mkBinaryRelease rec {
    pname = "kakehashi";
    version = "0.3.0";
    hashes = {
      "aarch64-darwin" = "sha256-tuMx+xkBLh8dyQhvB4pCKjEd9Zkg+CclHbVexFZ8ZXQ=";
      "x86_64-darwin" = "sha256-NdmkzAk6hBghu/9gmJ1QwGAuPS7u7K+YE2xoFr23k6M=";
      "aarch64-linux" = "sha256-lgB/J/FeBlklA1qS4hgGup15ulzh13QmKnrUDOnxKYI=";
      "x86_64-linux" = "sha256-phKlxTDjStxULip2nhwl6mgh5g6AIfovwty19o9m03o=";
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
    version = "0.5.6";
    hashes = {
      "aarch64-darwin" = "sha256-1tnFxE6vs7qR0Wh10lZLTCM7YjLABw45p3176Zr9Dik=";
      "x86_64-darwin" = "sha256-NXldfuJf9B80VD9sUIku8NoXuC6nwzDEjgxbmHoNz/Q=";
      "aarch64-linux" = "sha256-ExDxrJnYX097ASfGiL6UmH8dnxdT6FU2osiQYPtvQcc=";
      "x86_64-linux" = "sha256-ztuyFtFQWwi1asXAmEIH2sIW0jI22OMbhISxn14CLmk=";
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

  # biome - A toolchain for web projects (formatter + linter)
  # nixpkgs の更新が遅いため overlay でバージョン管理
  # Renovate: datasource=github-releases depName=biomejs/biome
  biome = mkBinaryRelease rec {
    pname = "biome";
    version = "2.4.6";
    hashes = {
      "aarch64-darwin" = "sha256-hFKxF18pe2nFtx/jvQRLOBp4yBLXwPQ3Y4/LOjJZc8k=";
      "x86_64-darwin" = "sha256-Fp8/MdG9i+CfGE7KVRhOcdBEnvV8eepW0CAjWHCUMfs=";
      "aarch64-linux" = "sha256-LaC40Cjnf3eJAKyE4dRLvHAzLan/2uPsOqBDVfM5+no=";
      "x86_64-linux" = "sha256-a8GS8fCzSVRDRy2VvU2/yTcsF/esUSVtY1GSylJdpZ0=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    url = platform: "https://github.com/biomejs/biome/releases/download/%40biomejs%2Fbiome%40${version}/biome-${platform}";
    meta = {
      description = "A toolchain for web projects (formatter + linter)";
      homepage = "https://github.com/biomejs/biome";
    };
  };

  # copilot - GitHub Copilot CLI
  # nixpkgs の更新が遅いため overlay でバージョン管理
  # Uses pre-built static binaries from npm platform packages
  # Renovate: datasource=npm depName=@github/copilot
  copilot = mkBinaryRelease rec {
    pname = "github-copilot-cli";
    version = "1.0.2";
    hashes = {
      "aarch64-darwin" = "sha256-S6dk8h8ZUPZxID3/LU2ONSfi5kmDhDtORDZlfOksGts=";
      "x86_64-darwin" = "sha256-rzfL+kgRvm7gI9jYcOA4qJqxPaxQFNNbgEewrRM5YUQ=";
      "aarch64-linux" = "sha256-9FH/UlDyGodGMQuLlDLwUU8yhHonq4BdBu/+4eIF3pY=";
      "x86_64-linux" = "sha256-rUeRZHi603jsU9IqqTmcrRphFOrwV8xC5x52qN9enMA=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    url = platform: "https://registry.npmjs.org/@github/copilot-${platform}/-/copilot-${platform}-${version}.tgz";
    format = "tgz";
    binName = "copilot";
    binPath = "source/copilot";
    meta = {
      description = "GitHub Copilot CLI";
      homepage = "https://github.com/github/copilot-cli";
      license = "unfree";
    };
  };
}
