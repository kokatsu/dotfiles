# Custom overlays for fixing build issues
{
  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = _final: prev: let
    version = "2.1.15";
    hashes = {
      "aarch64-darwin" = "sha256-zGJ8DvWuGSwF0ALyc+Y32GdpIJC9I+/9XvUgaQ25XnE=";
      "x86_64-darwin" = "sha256-3fCDEsfIDRGr43mPjBtW+VRFpVDNZOEbsz7kV3uChkg=";
      "aarch64-linux" = "sha256-IKUgJWt4r/VtQnPWGMl5ZZE+BBqFD+bOq5txT1fjlVQ=";
      "x86_64-linux" = "sha256-N/jodLjQfztgo7ZsegEDSDfR4zPrQVUtCTLXhCVehi0=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    hash = hashes.${system} or (throw "No hash for system: ${system}");
  in {
    claude-code = prev.stdenvNoCC.mkDerivation {
      pname = "claude-code";
      inherit version;

      src = prev.fetchurl {
        url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude";
        inherit hash;
      };

      dontUnpack = true;

      # バイナリはスタティックリンクされているため、autoPatchelfは不要

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp $src $out/bin/claude
        chmod +x $out/bin/claude
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Claude Code - an agentic coding tool";
        homepage = "https://github.com/anthropics/claude-code";
        license = licenses.unfree;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
        mainProgram = "claude";
      };
    };
  };

  # Pin vue-language-server to 3.0.8
  vue-language-server-pin = _final: prev: let
    # pnpmDeps hash differs between platforms due to native dependencies
    pnpmDepsHash =
      if prev.stdenv.hostPlatform.isDarwin
      then "sha256-KTpi7aldU9GBDwRwh51foePvoDEmEKhYDhNFGRXgeko="
      else "sha256-0H7j/TlVTkQ5dGlm1AgvtXYa+pPnkvadlNGygEaB85k=";
  in {
    vue-language-server = prev.vue-language-server.overrideAttrs (old: rec {
      version = "3.0.8";
      src = prev.fetchFromGitHub {
        owner = "vuejs";
        repo = "language-tools";
        rev = "v${version}";
        hash = "sha256-bUy1H481oxoddprj4WJaZdwbQA6a3SaJ92I/PJubltc=";
      };
      pnpmDeps = prev.fetchPnpmDeps {
        inherit (old) pname;
        inherit version src;
        fetcherVersion = 1;
        hash = pnpmDepsHash;
      };
    });
  };
  # Add termframe package (not in nixpkgs)
  termframe = _final: prev: {
    termframe = prev.rustPlatform.buildRustPackage rec {
      pname = "termframe";
      version = "0.7.4";

      src = prev.fetchFromGitHub {
        owner = "pamburus";
        repo = "termframe";
        rev = "v${version}";
        hash = "sha256-jAcutfzHYLPTF37dZo9gbGQ9WjIxqsYq2RONZP+xsUo=";
      };

      cargoHash = "sha256-7KUG9qsMtm9utF7w6PQkCfjw0HVCXnZ0tMHprp+cS3o=";

      nativeBuildInputs = [prev.pkg-config];
      buildInputs = prev.lib.optionals prev.stdenv.hostPlatform.isDarwin [
        prev.libiconv
      ];

      meta = with prev.lib; {
        description = "Terminal output SVG screenshot tool";
        homepage = "https://github.com/pamburus/termframe";
        license = licenses.mit;
        maintainers = [];
      };
    };
  };

  # Fix cava build on aarch64-darwin
  # iniparser's dependency unity-test has C++ compilation issues with new clang
  cava-darwin-fix = _final: prev: {
    iniparser = prev.iniparser.overrideAttrs (_old: {
      # Skip tests to avoid building unity-test
      doCheck = false;
    });
  };

  # Use forked git-graph with --current option and ANSI color wrapping fix
  # Also fixes build on aarch64-darwin (libz-sys crate can't find zlib.h)
  git-graph-fork = _final: prev: let
    forkedSrc = prev.fetchFromGitHub {
      owner = "kokatsu";
      repo = "git-graph";
      rev = "fix/ansi-color-wrap";
      hash = "sha256-n4mcZxy5MYfMQCYERH5zQBPkmW4l6RFahCBCwrnCYoU=";
    };
  in {
    git-graph = prev.git-graph.overrideAttrs (old: {
      src = forkedSrc;
      cargoDeps = prev.rustPlatform.fetchCargoVendor {
        inherit (old) pname;
        version = "fork";
        src = forkedSrc;
        hash = "sha256-a7Jo/kHuQH7OQrzAMY63jFEOPfnYKAb4AW65V5BEfWM=";
      };
      # Mark as not broken
      meta = old.meta // {broken = false;};
      # Add zlib to build inputs (darwin fix)
      buildInputs = (old.buildInputs or []) ++ [prev.zlib];
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.pkg-config];
      # Set environment variables for zlib
      LIBZ_SYS_STATIC = "0";
      PKG_CONFIG_PATH = "${prev.zlib.dev}/lib/pkgconfig";
    });
  };

  # Fix jp2a build on darwin (marked as broken)
  jp2a-darwin-fix = _final: prev: {
    jp2a = prev.jp2a.overrideAttrs (old: {
      meta = old.meta // {broken = false;};
    });
  };

  # Fix LDC on macOS 26+ (Darwin 25+)
  # The ldc2.conf references a non-existent compiler-rt directory
  # and the target triple conflicts with Nix cc-wrapper
  ldc-darwin-fix = _final: prev: {
    ldc = prev.ldc.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + prev.lib.optionalString prev.stdenv.hostPlatform.isDarwin ''
          # Remove non-existent compiler-rt directory from lib-dirs
          if [ -f "$out/etc/ldc2.conf" ]; then
            sed -i.bak 's|"[^"]*lib/clang/[0-9]*/lib/darwin".*||' "$out/etc/ldc2.conf"
          fi
        '';
    });
  };

  # k1LoW/deck - Markdown to Google Slides
  deck = _final: prev: {
    deck-slides = prev.buildGoModule rec {
      pname = "deck-slides";
      version = "1.22.1";

      src = prev.fetchFromGitHub {
        owner = "k1LoW";
        repo = "deck";
        rev = "v${version}";
        hash = "sha256-3p3/xPtpTtVtNbyJrHyOVbJS4qPea98gFV6u7WSYzWs=";
      };

      vendorHash = "sha256-ae/WY+CnEMp0HJ5dlaloyEF2kSCRWUkBfIOv5baXxjg=";

      # テストはvendorの不整合でfailするためスキップ
      doCheck = false;

      meta = with prev.lib; {
        description = "A tool for creating deck using Markdown and Google Slides";
        homepage = "https://github.com/k1LoW/deck";
        license = licenses.mit;
      };
    };
  };
}
