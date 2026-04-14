let
  lib = import ./lib.nix;
  inherit (lib) mkBinaryRelease;
in {
  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = mkBinaryRelease rec {
    pname = "claude-code";
    version = "2.1.108";
    hashes = {
      "aarch64-darwin" = "sha256-jWYWMxOXawBFuCnjfrP8zLEM5v1+BKbbhdLDkV/4quw=";
      "x86_64-darwin" = "sha256-nhmtquNwnOWRfYvy+qZp9WBFm/JAogVN5OXom6vQVGo=";
      "aarch64-linux" = "sha256-e+8ffc9koiH8ZlcaF2ymIGCIvsSGE6RstPpjKBacC9E=";
      "x86_64-linux" = "sha256-H2QWdusIbOr9dqX1H/smC5SPofbXeZHYzW5IAmff/zc=";
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

  # rgx - Terminal regex tester (regex101 for the terminal)
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=brevity1swos/rgx
  rgx-cli = mkBinaryRelease rec {
    pname = "rgx-cli";
    version = "0.10.2";
    hashes = {
      "aarch64-darwin" = "sha256-svj9fPg99jO036JD8tRWFSvEm0fVdFJWHtnWCPqxWTk=";
      "x86_64-darwin" = "sha256-yDD2RgV21fjIgf92LR38YaqR6lnQGEbNnv5CvewyoQ8=";
      "aarch64-linux" = "sha256-CczwC0MDiiya6TmvY7+vVYi07Bu6HbyyzHIgHT76Oxc=";
      "x86_64-linux" = "sha256-pbsmwYWaIonP3urHl2DPkkhjH2RxEgdpZ2E6Fvn69Z8=";
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
