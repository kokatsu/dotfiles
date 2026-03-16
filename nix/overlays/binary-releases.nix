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
    version = "2.1.76";
    hashes = {
      "aarch64-darwin" = "sha256-/+ki9PSsVC9O2+6rvOKnSSMI0DTGaiQnyuxcMcObccg=";
      "x86_64-darwin" = "sha256-KhPZo8oP4zD9eGNBiXry5SUAZru7H9y2z9/6UM8PkP4=";
      "aarch64-linux" = "sha256-QPdTwH8HDfNMqD5AD3Rqgnmj/TQ5Z6RT2fv6svPKes0=";
      "x86_64-linux" = "sha256-gBoIVnbD1UOSxC6OQ8RJR998UhMjVldffZJnxPItaZI=";
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
    version = "0.5.7";
    hashes = {
      "aarch64-darwin" = "sha256-mP8LXcTPZExiuLLxfxyAB7gW7YGOX6Uh8pTO44ysT5s=";
      "x86_64-darwin" = "sha256-i6NKmW0EV/Mppy3LALt12xA7fvV0zWH9KBSmg3VpYWM=";
      "aarch64-linux" = "sha256-oLV2rp0PvEklSRDd+oOCNPYXhg8eLJ+ArjO07aO7mmA=";
      "x86_64-linux" = "sha256-dP7y08c9l+MQQxSM7MUtlTZcocivhZzjVjY6dB+1vVk=";
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
    version = "2.4.7";
    hashes = {
      "aarch64-darwin" = "sha256-xziDa44xrCV4XmUd7qsP0PJk80VcrVCRtO4KdPnx9Ao=";
      "x86_64-darwin" = "sha256-AeRd80asKC2/iSqnmy4i0iwsHcwVqLbElGlLkNIN41A=";
      "aarch64-linux" = "sha256-vEdso4TgDjqLhlA61JQXa8ZQY8Gp51ftTcMB0jOZTM0=";
      "x86_64-linux" = "sha256-qb1AYSaSFMlltGiGfBCYmW1rGyULfizqfQslopsN4rA=";
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
    version = "1.0.4";
    hashes = {
      "aarch64-darwin" = "sha256-ExxjK4oWxp2WlP9go9iaz5oBC99/D8KL/gqE+m4bHXk=";
      "x86_64-darwin" = "sha256-OHdWwzPzB5jAWknbl4PBkGJ+clhfJlKvdrHOyxRZOpg=";
      "aarch64-linux" = "sha256-D/oAMzfZ5Kq5uJpMcqRNfujX0ipHnNmWLNiwdZeSBlc=";
      "x86_64-linux" = "sha256-fMYmE/Q3NHAMOTrxEetV5hikQCVx5F6RzSFPF8fmMts=";
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
