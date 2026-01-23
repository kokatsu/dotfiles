# Custom overlays for fixing build issues
{
  # Claude Code - agentic coding tool
  # Managed by .github/workflows/update-claude-code.yml (not Renovate)
  claude-code = _final: prev: let
    version = "2.1.17";
    hashes = {
      "aarch64-darwin" = "sha256-HYGafA7RrWJ19CzytnBBq4Ca+xzTU3xu1uYYuI5aBTE=";
      "x86_64-darwin" = "sha256-ZZrYaFYDgT0QrffGjfw7BUaM0ceCRNM7wGV4P7Nsqmo=";
      "aarch64-linux" = "sha256-whYlwPlie6Qxxb41c8T4oN7mS1fg0RIgkwwp3hAo+Ck=";
      "x86_64-linux" = "sha256-Eai8LezhzXcXpMETiDpXMJVRFHVUVZXSsOlvGI1lHg8=";
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
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=pamburus/termframe
  termframe = _final: prev: let
    version = "0.7.6";
    hashes = {
      "aarch64-darwin" = "sha256-BDdd9bEsxuQzs/lNHDFJMXnkIEomOZPuQLp6tfDZhVk=";
      "x86_64-darwin" = "sha256-USphR1LE7SZTndwTw2dEgQ+Xv3K1lm7aWCJ/9pa4Gj4=";
      "aarch64-linux" = "sha256-LjGUJz/JtV6y9XulCjsaUk5vdqvJkErUpQytB2z09i0=";
      "x86_64-linux" = "sha256-nfJxS3AnCNiYmwFXNMXBdrX4b6rXsgbJODQ7pILusVk=";
    };
    platformMap = {
      "aarch64-darwin" = "macos-arm64";
      "x86_64-darwin" = "macos-x86_64";
      "aarch64-linux" = "linux-arm64-gnu";
      "x86_64-linux" = "linux-x86_64-gnu";
    };
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    hash = hashes.${system} or (throw "No hash for system: ${system}");
  in {
    termframe = prev.stdenvNoCC.mkDerivation {
      pname = "termframe";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/pamburus/termframe/releases/download/v${version}/termframe-${platform}.tar.gz";
        inherit hash;
      };

      sourceRoot = ".";

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp termframe $out/bin/
        chmod +x $out/bin/termframe
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Terminal output SVG screenshot tool";
        homepage = "https://github.com/pamburus/termframe";
        license = licenses.mit;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
        mainProgram = "termframe";
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
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=k1LoW/deck
  deck = _final: prev: let
    version = "1.22.1";
    hashes = {
      "aarch64-darwin" = "sha256-+J/yUip6L8L6LeQPBKT/r14rdkZL50HQPokryMx0sQY=";
      "x86_64-darwin" = "sha256-YR8I4ioBqW8cU+H4yrROj/p1GgVBVcuTqpkrGlDHzlQ=";
      "aarch64-linux" = "sha256-rt4AiXyrxGZa/tGPsYW6vSknvjaYpO183rqBsuTzUu8=";
      "x86_64-linux" = "sha256-08MUun13t2umwzrIw0aCBMCiZc+HodeWK/RMHUiAN0w=";
    };
    platformMap = {
      "aarch64-darwin" = {
        platform = "darwin_arm64";
        ext = "zip";
      };
      "x86_64-darwin" = {
        platform = "darwin_amd64";
        ext = "zip";
      };
      "aarch64-linux" = {
        platform = "linux_arm64";
        ext = "tar.gz";
      };
      "x86_64-linux" = {
        platform = "linux_amd64";
        ext = "tar.gz";
      };
    };
    inherit (prev.stdenv.hostPlatform) system;
    platformInfo = platformMap.${system} or (throw "Unsupported system: ${system}");
    hash = hashes.${system} or (throw "No hash for system: ${system}");
  in {
    deck-slides = prev.stdenvNoCC.mkDerivation {
      pname = "deck-slides";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/k1LoW/deck/releases/download/v${version}/deck_v${version}_${platformInfo.platform}.${platformInfo.ext}";
        inherit hash;
      };

      nativeBuildInputs = prev.lib.optionals (platformInfo.ext == "zip") [prev.unzip];

      sourceRoot = ".";

      unpackPhase =
        if platformInfo.ext == "zip"
        then ''
          runHook preUnpack
          unzip $src
          runHook postUnpack
        ''
        else ''
          runHook preUnpack
          tar -xzf $src
          runHook postUnpack
        '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp deck $out/bin/deck-slides
        chmod +x $out/bin/deck-slides
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "A tool for creating deck using Markdown and Google Slides";
        homepage = "https://github.com/k1LoW/deck";
        license = licenses.mit;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
        mainProgram = "deck-slides";
      };
    };
  };

  # ccusage - Claude API usage viewer
  # Uses pre-built package from npm (bundled, no runtime dependencies)
  # Renovate: datasource=npm depName=ccusage
  ccusage = _final: prev: {
    ccusage = prev.stdenvNoCC.mkDerivation rec {
      pname = "ccusage";
      version = "18.0.5";

      src = prev.fetchurl {
        url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
        hash = "sha256-Co9+jFDk4WmefrDnJvladjjYk+XHhYYEKNKb9MbrkU8=";
      };

      nativeBuildInputs = [prev.makeWrapper];

      unpackPhase = ''
        runHook preUnpack
        mkdir -p source
        tar -xzf $src -C source --strip-components=1
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/{bin,lib/ccusage}
        cp -r source/{dist,package.json,config-schema.json} $out/lib/ccusage/
        makeWrapper ${prev.nodejs}/bin/node $out/bin/ccusage \
          --add-flags "$out/lib/ccusage/dist/index.js"
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Claude API usage viewer";
        homepage = "https://github.com/ryoppippi/ccusage";
        license = licenses.mit;
        mainProgram = "ccusage";
      };
    };
  };

  # secretlint - Secret linting tool
  # Uses custom package.json to bundle secretlint with rule preset
  # Renovate: datasource=npm depName=secretlint
  secretlint = _final: prev: let
    version = "11.3.0";
    # Use vendored package.json and package-lock.json that include rule preset
    packageJson = prev.writeText "package.json" (builtins.readFile ../npm-locks/secretlint/package.json);
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/secretlint/package-lock.json);
  in {
    secretlint = prev.buildNpmPackage {
      pname = "secretlint";
      inherit version;

      src = prev.runCommand "secretlint-src" {} ''
        mkdir -p $out
        cp ${packageJson} $out/package.json
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-WGYktC3FAMLzXsflnhuFM6PPjuDK7y/uw0vQ8fswT6s=";

      dontNpmBuild = true;

      meta = with prev.lib; {
        description = "Pluggable linting tool to prevent commit secret/credential file";
        homepage = "https://github.com/secretlint/secretlint";
        license = licenses.mit;
        mainProgram = "secretlint";
      };
    };
  };

  # cssmodules-language-server - CSS Modules LSP
  # Uses buildNpmPackage from GitHub source
  # Renovate: datasource=npm depName=cssmodules-language-server
  cssmodules-language-server = _final: prev: {
    cssmodules-language-server = prev.buildNpmPackage rec {
      pname = "cssmodules-language-server";
      version = "1.5.2";

      src = prev.fetchFromGitHub {
        owner = "antonk52";
        repo = "cssmodules-language-server";
        rev = "v${version}";
        hash = "sha256-9RZNXdmBP4OK7k/0LuuvqxYGG2fESYTCFNCkAWZQapk=";
      };

      npmDepsHash = "sha256-1CnCgut0Knf97+YHVJGUZqnRId/BwHw+jH1YPIrDPCA=";

      meta = with prev.lib; {
        description = "Language server for CSS Modules";
        homepage = "https://github.com/antonk52/cssmodules-language-server";
        license = licenses.mit;
        mainProgram = "cssmodules-language-server";
      };
    };
  };

  # unocss-language-server - UnoCSS LSP
  # Uses pre-built package from npm with vendored package-lock.json
  # Renovate: datasource=npm depName=unocss-language-server
  unocss-language-server = _final: prev: let
    version = "0.1.8";
    tarball = prev.fetchurl {
      url = "https://registry.npmjs.org/unocss-language-server/-/unocss-language-server-${version}.tgz";
      hash = "sha256-16xM1/6Um2FMj4i8Ua3uP7to2PiRX4Z8oDnUwnn232s=";
    };
    # Pre-generated package-lock.json (npm install --package-lock-only --ignore-scripts)
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/unocss-language-server/package-lock.json);
  in {
    unocss-language-server = prev.buildNpmPackage {
      pname = "unocss-language-server";
      inherit version;

      src = prev.runCommand "unocss-language-server-src" {} ''
        mkdir -p $out
        tar -xzf ${tarball} -C $out --strip-components=1
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-yP2foN8e4l6dtE/uDFyKuSws44SCEvqe6jPLeaJr4Mk=";

      # Already pre-built
      dontNpmBuild = true;

      meta = with prev.lib; {
        description = "Language server for UnoCSS";
        homepage = "https://github.com/xna00/unocss-language-server";
        license = licenses.mit;
        mainProgram = "unocss-language-server";
      };
    };
  };

  # agent-browser - Browser automation agent
  # Uses pre-built native binaries from npm package
  # Renovate: datasource=npm depName=agent-browser
  agent-browser = _final: prev: let
    version = "0.6.0";
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
  in {
    agent-browser = prev.stdenvNoCC.mkDerivation {
      pname = "agent-browser";
      inherit version;

      src = prev.fetchurl {
        url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
        hash = "sha256-sf+IP0rQqZiboL7E9j2YVQBGtPPtMvcE/R9fplWyknk=";
      };

      unpackPhase = ''
        runHook preUnpack
        mkdir -p source
        tar -xzf $src -C source --strip-components=1
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp source/bin/agent-browser-${platform} $out/bin/agent-browser
        chmod +x $out/bin/agent-browser
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Browser automation agent";
        homepage = "https://github.com/anthropics/agent-browser";
        license = licenses.mit;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
        mainProgram = "agent-browser";
      };
    };
  };
}
