# Custom overlays for fixing build issues
{
  # marksman - Markdown LSP (binary release)
  # nixpkgs の marksman は .NET 依存で Swift ビルド失敗するため GitHub バイナリを使用
  # Renovate: datasource=github-releases depName=artempyanykh/marksman
  marksman-binary = _final: prev: let
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
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    hash = hashes.${system} or (throw "No hash for system: ${system}");
  in {
    marksman = prev.stdenvNoCC.mkDerivation {
      pname = "marksman";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/artempyanykh/marksman/releases/download/${version}/marksman-${platform}";
        inherit hash;
      };

      dontUnpack = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp $src $out/bin/marksman
        chmod +x $out/bin/marksman
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Markdown LSP server";
        homepage = "https://github.com/artempyanykh/marksman";
        license = licenses.mit;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
        mainProgram = "marksman";
      };
    };
  };

  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = _final: prev: let
    version = "2.1.63";
    hashes = {
      "aarch64-darwin" = "sha256-lPgTVhUZZ2qVE149NjHLx0oUiDIiryDe9tUEDRk81ec=";
      "x86_64-darwin" = "sha256-Sp1hnN6TEB3TJ5IRzxBT25Qvl9ajI87BtXDVL0Px86k=";
      "aarch64-linux" = "sha256-aWwvKiKiM3Xp1+4mrwr/QXzUo6jLcE8k5LqcdKTHjTc=";
      "x86_64-linux" = "sha256-1vBybLjpS3owwkOWRSm6kTXmQsQNITTKCfX4RQcUcbQ=";
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
    version = "0.8.1";
    hashes = {
      "aarch64-darwin" = "sha256-NuoC0bkYQHRcvC1ha5q9Qhqs9yZ0bv5IVKDphZ4widg=";
      "x86_64-darwin" = "sha256-VDyuSAvPzZc7XGzAhmIsDHTSUh0JbopG2zNhyxBxh1M=";
      "aarch64-linux" = "sha256-bxTKW258ieuGitiPbESZoF/pecay9V7mU0NCUkMF4kM=";
      "x86_64-linux" = "sha256-jttPwFHYl7s08vIFIHfLAygUaUqkWTeo39vCdzIGgg4=";
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

  # win32yank - Windows clipboard tool for WSL
  # Renovate: datasource=github-releases depName=equalsraf/win32yank
  win32yank = _final: prev: {
    win32yank = prev.stdenvNoCC.mkDerivation {
      pname = "win32yank";
      version = "0.1.1";

      src = prev.fetchzip {
        url = "https://github.com/equalsraf/win32yank/releases/download/v0.1.1/win32yank-x64.zip";
        hash = "sha256-4ivE1cYZhYs4ibx5oiYMOhbse9bdOomk7RjgdVl5lD0=";
        stripRoot = false;
      };

      dontFixup = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp $src/win32yank.exe $out/bin/
        chmod +x $out/bin/win32yank.exe
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Windows clipboard tool for WSL";
        homepage = "https://github.com/equalsraf/win32yank";
        license = licenses.mit;
        platforms = ["x86_64-linux"];
        mainProgram = "win32yank.exe";
      };
    };
  };

  # Fix plotly/optuna build failure (Kaleido subprocess crash on macOS CI)
  plotly-test-fix = _final: prev: {
    python3 = prev.python3.override {
      packageOverrides = _pyfinal: pyprev: {
        plotly = pyprev.plotly.overrideAttrs {
          doInstallCheck = false;
        };
        optuna = pyprev.optuna.overrideAttrs {
          doInstallCheck = false;
        };
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

  # Use forked git-graph with:
  # - --current option
  # - ANSI color wrapping fix
  # - HEAD highlight feature
  # - Performance optimizations for graph construction
  # Also fixes build on aarch64-darwin (libz-sys crate can't find zlib.h)
  git-graph-fork = _final: prev: let
    forkedSrc = prev.fetchFromGitHub {
      owner = "kokatsu";
      repo = "git-graph";
      rev = "perf/optimize-graph-construction";
      hash = "sha256-i1E6Rxc+LqEetSqlhrHciybm+DQIAYeJfzWGO87G5+I=";
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
    version = "1.23.0";
    hashes = {
      "aarch64-darwin" = "sha256-UcKJ4lwdyNi+h6bMbyEJhsdizI/x1cQU6mE1bTreF6I=";
      "x86_64-darwin" = "sha256-KccUz9rrM0X0yyCDHNNfP/7IbGRu+JR5nC7n1pNoJ5E=";
      "aarch64-linux" = "sha256-dBRTGxGgkEStG9nypMm/XSZB+Qiuktz7v87kJZxvSHw=";
      "x86_64-linux" = "sha256-NfYJn0lq7zBw2Kr6cmOUYdGGoJlwfCzgAXFBSrp/2x8=";
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
      version = "18.0.8";

      src = prev.fetchurl {
        url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
        hash = "sha256-c2xz9hXNMyRkbYCHTuf07vHuUdKtYvPaujtcPIY9t7g=";
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
        makeWrapper ${prev.bun}/bin/bun $out/bin/ccusage \
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
    version = "11.3.1";
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

      npmDepsHash = "sha256-TtV+h0HTPBKSCVwoFqj+jZNdzucctdcBij3ccpZQP+0=";

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
  agent-browser = final: prev: let
    version = "0.15.1";
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    # Pre-generated package-lock.json (npm install --package-lock-only --ignore-scripts)
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/agent-browser/package-lock.json);
  in {
    agent-browser = prev.buildNpmPackage {
      pname = "agent-browser";
      inherit version;

      src = prev.fetchurl {
        url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
        hash = "sha256-4bmdWjJXqDL9poGMAneIAimiBPAHgLXj/gTv3aTT66Q=";
      };

      npmDepsHash = "sha256-SscCV0TEB74gNztdC0Y/wPfehn+7YwVrSpEsRA9Sf1c=";
      dontNpmBuild = true;
      npmPackFlags = ["--ignore-scripts"];
      # --legacy-peer-deps: upstream has conflicting peer deps
      # (zod ^3.22.4 vs @anthropic-ai/claude-agent-sdk requiring zod ^4.0.0)
      npmFlags = ["--ignore-scripts" "--legacy-peer-deps"];

      # Set correct PLAYWRIGHT_BROWSERS_PATH during build
      PLAYWRIGHT_BROWSERS_PATH = final.playwright-driver.browsers;

      nativeBuildInputs = [prev.makeWrapper];

      postPatch = ''
        cp ${packageLock} package-lock.json
      '';

      postInstall = ''
        # Replace node wrapper with native binary
        rm -f $out/bin/agent-browser
        mkdir -p $out/lib/agent-browser
        cp $out/lib/node_modules/agent-browser/bin/agent-browser-${platform} $out/lib/agent-browser/agent-browser
        chmod +x $out/lib/agent-browser/agent-browser

        makeWrapper $out/lib/agent-browser/agent-browser $out/bin/agent-browser \
          --set AGENT_BROWSER_HOME $out/lib/node_modules/agent-browser \
          --unset PLAYWRIGHT_BROWSERS_PATH \
          --set-default PLAYWRIGHT_BROWSERS_PATH ${final.playwright-driver.browsers} \
          --prefix PATH : ${prev.lib.makeBinPath [prev.nodejs]}
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

  # keifu - Git commit graph TUI visualizer
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=trasta298/keifu
  keifu = _final: prev: let
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
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    hash = hashes.${system} or (throw "No hash for system: ${system}");
  in {
    keifu = prev.stdenvNoCC.mkDerivation {
      pname = "keifu";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/trasta298/keifu/releases/download/v${version}/keifu-v${version}-${platform}.tar.gz";
        inherit hash;
      };

      sourceRoot = ".";

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp keifu $out/bin/
        chmod +x $out/bin/keifu
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Git commit graph TUI visualizer";
        homepage = "https://github.com/trasta298/keifu";
        license = licenses.mit;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
        mainProgram = "keifu";
      };
    };
  };

  # Fix playwright-driver.browsers to include chromium revision 1208
  # Required for agent-browser 0.8.x which uses Playwright 1.58+
  # nixpkgs has playwright-driver 1.57+ but browsers.json still uses revision 1200
  playwright-browsers-fix = _final: prev: let
    inherit (prev.stdenv.hostPlatform) system;

    # Chrome for Testing revision 1208 (Playwright 1.58)
    chromiumVersion = "145.0.7632.6";
    revision = "1208";

    # Platform-specific configurations
    platformConfig = {
      "x86_64-linux" = {
        suffix = "linux64";
        chromiumHash = "sha256-akvAXdfBKdjDQBnWTDX0WbmP+niXthXlyB9feeq8kyw=";
        headlessShellHash = "sha256-/xskLzTc9tTZmu1lwkMpjV3QV7XjP92D/7zRcFuVWT8=";
      };
      "aarch64-linux" = {
        suffix = "linux-arm64";
        # TODO: Add hashes for aarch64-linux when needed
        chromiumHash = "";
        headlessShellHash = "";
      };
      "x86_64-darwin" = {
        suffix = "mac-x64";
        # TODO: Add hashes for x86_64-darwin when needed
        chromiumHash = "";
        headlessShellHash = "";
      };
      "aarch64-darwin" = {
        suffix = "mac-arm64";
        chromiumHash = "sha256-qXdgHeBS5IFIa4hZVmjq0+31v/uDPXHyc4aH7Wn2E7E=";
        headlessShellHash = "sha256-45DjMIu0t7IEYdXOmIqpV/1/MKdEfx/8T7DWagh6Zhc=";
      };
    };

    config = platformConfig.${system} or (throw "Unsupported system: ${system}");

    # Chromium browser (revision 1208)
    chromium-1208 = prev.fetchzip {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${chromiumVersion}/${config.suffix}/chrome-${config.suffix}.zip";
      hash = config.chromiumHash;
      stripRoot = false;
    };

    # Chromium headless shell (revision 1208)
    chromium-headless-shell-1208 = prev.fetchzip {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${chromiumVersion}/${config.suffix}/chrome-headless-shell-${config.suffix}.zip";
      hash = config.headlessShellHash;
      stripRoot = false;
    };

    # Original browsers from nixpkgs
    originalBrowsers = prev.playwright-driver.browsers;
  in {
    playwright-driver =
      prev.playwright-driver
      // {
        browsers = prev.linkFarm "playwright-browsers" (
          # Keep all original browsers
          (builtins.listToAttrs (
            map (name: {
              inherit name;
              value = "${originalBrowsers}/${name}";
            }) (builtins.attrNames (builtins.readDir originalBrowsers))
          ))
          // (prev.lib.optionalAttrs (config.chromiumHash != "") {
            # Add chromium revision 1208
            "chromium-${revision}" = chromium-1208;
            "chromium_headless_shell-${revision}" = chromium-headless-shell-1208;
          })
        );
      };
  };

  # playwright-cli - Playwright CLI for coding agents
  # Uses custom package.json to bundle @playwright/cli
  # Renovate: datasource=npm depName=@playwright/cli
  playwright-cli = _final: prev: let
    version = "0.1.1";
    packageJson = prev.writeText "package.json" (builtins.readFile ../npm-locks/playwright-cli/package.json);
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/playwright-cli/package-lock.json);
  in {
    playwright-cli = prev.buildNpmPackage {
      pname = "playwright-cli";
      inherit version;

      src = prev.runCommand "playwright-cli-src" {} ''
        mkdir -p $out
        cp ${packageJson} $out/package.json
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-d223ZtnBLv1zoAElkqJLaYpdvkQJr5m9WIkTUXO5fJg=";

      dontNpmBuild = true;

      nativeBuildInputs = [prev.makeWrapper];

      postInstall = ''
        mkdir -p $out/bin
        makeWrapper ${prev.nodejs}/bin/node $out/bin/playwright-cli \
          --add-flags "$out/lib/node_modules/playwright-cli-wrapper/node_modules/@playwright/cli/playwright-cli.js"
      '';

      meta = with prev.lib; {
        description = "Playwright CLI for coding agents";
        homepage = "https://github.com/microsoft/playwright-cli";
        license = licenses.asl20;
        mainProgram = "playwright-cli";
      };
    };
  };

  # xdevplatform/playground - X API v2 simulator for testing
  # Renovate: datasource=github-releases depName=xdevplatform/playground
  x-api-playground = _final: prev: {
    x-api-playground = prev.buildGoModule rec {
      pname = "x-api-playground";
      version = "1.2.1";

      src = prev.fetchFromGitHub {
        owner = "xdevplatform";
        repo = "playground";
        rev = "v${version}";
        hash = "sha256-x80q79BytD1iN3P1X8NW+2OUXBRsBsjNDZvSABSHkV8=";
      };

      vendorHash = "sha256-sjhUfE6bysaSDQb8EkqL5wptdxgtcxt9+K+7Dic3le0=";

      # Skip tests as they may require network access
      doCheck = false;

      meta = with prev.lib; {
        description = "Local HTTP server that simulates X API v2 for testing";
        homepage = "https://github.com/xdevplatform/playground";
        license = licenses.mit;
        mainProgram = "playground";
      };
    };
  };

  # textlint - Pluggable linting tool for text and markdown
  # Uses custom package.json to bundle textlint with Japanese writing preset
  # Renovate: datasource=npm depName=textlint
  textlint = _final: prev: let
    version = "15.5.2";
    packageJson = prev.writeText "package.json" (builtins.readFile ../npm-locks/textlint/package.json);
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/textlint/package-lock.json);
  in {
    textlint = prev.buildNpmPackage {
      pname = "textlint";
      inherit version;

      src = prev.runCommand "textlint-src" {} ''
        mkdir -p $out
        cp ${packageJson} $out/package.json
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-2yEMpMJbTe8tHm9bPFTyaWD4mIiJDRlBJBYAgslC6cg=";

      dontNpmBuild = true;

      meta = with prev.lib; {
        description = "Pluggable linting tool for text and markdown";
        homepage = "https://github.com/textlint/textlint";
        license = licenses.mit;
        mainProgram = "textlint";
      };
    };
  };

  # cc-statusline - Fast Claude Code statusline tool (Zig)
  cc-statusline = _final: prev: {
    cc-statusline = prev.stdenvNoCC.mkDerivation {
      pname = "cc-statusline";
      version = "0.1.0";
      src = ../../tools/cc-statusline;
      nativeBuildInputs = [prev.zig prev.makeWrapper];
      dontConfigure = true;
      dontFixup = true;
      buildPhase = ''
        export HOME=$TMPDIR
        export XDG_CACHE_HOME=$TMPDIR/.cache
        zig build -Doptimize=ReleaseFast --prefix $out
      '';
      installPhase = ''
        wrapProgram $out/bin/cc-statusline \
          --set-default CC_STATUSLINE_THEME catppuccin-mocha
      '';
    };
  };

  # biome - A toolchain for web projects (formatter + linter)
  # nixpkgs の更新が遅いため overlay でバージョン管理
  # Renovate: datasource=github-releases depName=biomejs/biome
  biome = _final: prev: let
    version = "2.4.4";
    hashes = {
      "aarch64-darwin" = "sha256-6JARsXFKIOvUtoMyG6cYTOKnmij07j0zvadKTqdJBio=";
      "x86_64-darwin" = "sha256-T60NUBXrtr5SuJOY7Q6Qch7gI59M3qDDRyV6CihujYQ=";
      "aarch64-linux" = "sha256-cIz6oB0SsrsWScW32X894koXQfvPzwpGHF+b5Idcdgs=";
      "x86_64-linux" = "sha256-ulBzAX7AOnAOW5JwskVN99vsalEkYRu3hbaK5xdQbUU=";
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
    biome = prev.stdenvNoCC.mkDerivation {
      pname = "biome";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/biomejs/biome/releases/download/%40biomejs%2Fbiome%40${version}/biome-${platform}";
        inherit hash;
      };

      dontUnpack = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp $src $out/bin/biome
        chmod +x $out/bin/biome
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "A toolchain for web projects (formatter + linter)";
        homepage = "https://github.com/biomejs/biome";
        license = licenses.mit;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
        mainProgram = "biome";
      };
    };
  };

  # octorus - TUI tool for GitHub PR review
  # Renovate: datasource=github-releases depName=ushironoko/octorus
  octorus = _final: prev: {
    octorus = prev.rustPlatform.buildRustPackage rec {
      pname = "octorus";
      version = "0.5.3";

      src = prev.fetchFromGitHub {
        owner = "ushironoko";
        repo = "octorus";
        rev = "v${version}";
        hash = "sha256-p1ZkjoFrcsfpY/0w8NlVOn94VO4wEMtQkxOeI49LEaE=";
      };

      cargoHash = "sha256-Ginyyd1FqXx1t1KUxkc7jsqqePzlBF2ujMm4kwL9A/c=";

      # Skip tests (require GitHub authentication)
      doCheck = false;

      meta = with prev.lib; {
        description = "TUI tool for GitHub PR review with Vim-style keybindings";
        homepage = "https://github.com/ushironoko/octorus";
        license = licenses.mit;
        mainProgram = "or";
      };
    };
  };
}
