let
  lib = import ./lib.nix;
  inherit (lib) mkBinaryRelease;
in {
  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = mkBinaryRelease rec {
    pname = "claude-code";
    version = "2.1.138";
    hashes = {
      "aarch64-darwin" = "sha256-dZ0jzmJhk8ibyLNcXGyoqeM7nC5QTuFD5M0RmYh3QJc=";
      "x86_64-darwin" = "sha256-2Z06ev1jhBlDkGsR7YeRsO5H/lz5VgGouAXCCQABT1Q=";
      "aarch64-linux" = "sha256-aT7MpBpi1Y/uZgiEvZgspc3qtbJ3kl/N/ogM3wL5hnE=";
      "x86_64-linux" = "sha256-w8Vv+8Es8W5AwzaHyf5jYe0lDDWp4XGNDDjUkEn1+MM=";
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

  # kakehashi - Tree-sitter Language Server
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=atusy/kakehashi
  kakehashi = mkBinaryRelease rec {
    pname = "kakehashi";
    version = "0.5.0";
    hashes = {
      "aarch64-darwin" = "sha256-SfTEA5uPlXluRtLVXoPJ73m2UJjN3ElwqnEPp+zSDpE=";
      "x86_64-darwin" = "sha256-W1+MXHYSYjFj8QqKmIXtIat/dqk6257qdH6V8nCdBJY=";
      "aarch64-linux" = "sha256-YW3BJWx6GijmlSVO+tMWrA3JyJ+a7fr6bfWyOlZkPy8=";
      "x86_64-linux" = "sha256-/O5ca7o5lG76sFo+4IBoVE5xbtc8gYBExlmzfhMaIVo=";
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

  # DCD - D Completion Daemon (serve-d の補完バックエンド)
  # dcd-server / dcd-client の2バイナリを同梱。serve-d は dcd-server と直接通信するため
  # どちらも $out/bin に配置する必要がある。
  # Renovate: datasource=github-releases depName=dlang-community/DCD
  dcd = mkBinaryRelease rec {
    pname = "dcd";
    version = "0.16.2";
    hashes = {
      "aarch64-darwin" = "sha256-WvO183eZWB5oRZbRpny3wdzMe+WhJD6eA4f7FoHbFxU=";
      "x86_64-darwin" = "sha256-FUtV75znNLsdObbqSS9rixxy8flRRXNQTUMN7f6m77k=";
      "aarch64-linux" = "sha256-ZTXSUNDNo4g7zqWUacu5NvzPMdq9ijuaM9/hldRhTKo=";
      "x86_64-linux" = "sha256-QGrA29Hadd2asAgLaF0XD0xY/l3FeAfQMctBDu3aj+I=";
    };
    platformMap = {
      "aarch64-darwin" = "osx-aarch64";
      "x86_64-darwin" = "osx-x86_64";
      "aarch64-linux" = "linux-aarch64";
      "x86_64-linux" = "linux-x86_64";
    };
    url = platform: "https://github.com/dlang-community/DCD/releases/download/v${version}/dcd-v${version}-${platform}.tar.gz";
    format = "tar";
    # mkBinaryRelease は単一バイナリ前提なので installPhase を上書きして 2 バイナリ配置する
    extraAttrs = {
      sourceRoot = ".";
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp dcd-server dcd-client $out/bin/
        chmod +x $out/bin/dcd-server $out/bin/dcd-client
        runHook postInstall
      '';
    };
    meta = {
      description = "D Completion Daemon - autocompletion for the D programming language";
      homepage = "https://github.com/dlang-community/DCD";
      mainProgram = "dcd-server";
    };
  };

  # octorus - TUI tool for GitHub PR review
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=ushironoko/octorus
  octorus = mkBinaryRelease rec {
    pname = "octorus";
    version = "0.6.3";
    hashes = {
      "aarch64-darwin" = "sha256-kVv55cMmZH1tHOTJprgE4FqXoNXTHuiJVxU+cgoZN8Q=";
      "x86_64-darwin" = "sha256-+DLbp16Lk9ENe8q3MA08b82x3i+8XgoW9KQx5vYrEIw=";
      "aarch64-linux" = "sha256-UBhgnfK8Spa7DHK923P/50Y8VMSeSvVDC4vG2RhmGjc=";
      "x86_64-linux" = "sha256-dTAaUAhlIfcPXLKdoMaYl4i1gAoKHxcyJ//I3GvDBnw=";
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

  # rgx - Terminal regex tester (regex101 for the terminal)
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=brevity1swos/rgx
  rgx-cli = mkBinaryRelease rec {
    pname = "rgx-cli";
    version = "0.12.1";
    hashes = {
      "aarch64-darwin" = "sha256-e4wC//IyZS2YwDQe5iPNABEtZJVZYwuDMgAFnKCsWXo=";
      "x86_64-darwin" = "sha256-dSgJwotAZwrXBreQ0c6fILIzju4IaUngPfadEhESTSE=";
      "aarch64-linux" = "sha256-ols5kOeKmTm2Z9YGhb3J468ow5RRxIabObHRkLnqEt0=";
      "x86_64-linux" = "sha256-ZgjkDU7iwPpZjwuH9D1X/8IvQHIXk8UFCMNzt4D/ZA4=";
    };
    platformMap = {
      "aarch64-darwin" = "aarch64-apple-darwin";
      "x86_64-darwin" = "x86_64-apple-darwin";
      "aarch64-linux" = "aarch64-unknown-linux-gnu";
      "x86_64-linux" = "x86_64-unknown-linux-gnu";
    };
    url = platform: "https://github.com/brevity1swos/rgx/releases/download/v${version}/rgx-cli-${platform}.tar.xz";
    format = "tar";
    binName = "rgx";
    meta = {
      description = "Terminal regex tester with real-time matching and multi-engine support";
      homepage = "https://github.com/brevity1swos/rgx";
    };
  };
}
