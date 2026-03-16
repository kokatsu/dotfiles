{
  # Pin vue-language-server to 3.0.8
  vue-language-server-pin = _final: prev: let
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
      meta = old.meta // {broken = false;};
      buildInputs = (old.buildInputs or []) ++ [prev.zlib];
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.pkg-config];
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

  # Fix nodejs 22.x build failure (clang crash during V8 compilation on macOS)
  # Alias nodejs_22 to nodejs_24 so all dependent packages (gemini-cli, vtsls, etc.) build
  nodejs-22-fix = _final: prev: {
    nodejs_22 = prev.nodejs_24;
    nodejs-slim_22 = prev.nodejs-slim_24;
  };

  # Fix gemini-cli npm deps for nodejs_24 (npm 11 requires fetcher v2)
  gemini-cli-npm11-fix = _final: prev: {
    gemini-cli = prev.gemini-cli.overrideAttrs (old: {
      env =
        (old.env or {})
        // {
          NIX_NPM_FETCHER_VERSION = "2";
        };
      npmDeps = prev.fetchNpmDeps {
        inherit (old) src;
        name = "${old.pname}-${old.version}-npm-deps";
        hash = "sha256-qf/4ExlMfPi7OkhVs2AKrooWKA+MdA6m4sP7qoAnfRM=";
        fetcherVersion = 2;
      };
    });
  };

  # Fix playwright-driver.browsers to include chromium revision 1208
  # Required for agent-browser 0.8.x which uses Playwright 1.58+
  # nixpkgs has playwright-driver 1.57+ but browsers.json still uses revision 1200
  playwright-browsers-fix = _final: prev: let
    inherit (prev.stdenv.hostPlatform) system;

    chromiumVersion = "145.0.7632.6";
    revision = "1208";

    platformConfig = {
      "x86_64-linux" = {
        suffix = "linux64";
        chromiumHash = "sha256-akvAXdfBKdjDQBnWTDX0WbmP+niXthXlyB9feeq8kyw=";
        headlessShellHash = "sha256-/xskLzTc9tTZmu1lwkMpjV3QV7XjP92D/7zRcFuVWT8=";
      };
      "aarch64-linux" = {
        suffix = "linux-arm64";
        chromiumHash = "";
        headlessShellHash = "";
      };
      "x86_64-darwin" = {
        suffix = "mac-x64";
        chromiumHash = "sha256-+jpk7PuOK4bEurrGt3Z60uY50k4YgtlL2DxTwp/wbbg=";
        headlessShellHash = "sha256-qXeSBKiJDlmTur6oFc+bIxJEiI1ajUh5F8K7EmZcDK0=";
      };
      "aarch64-darwin" = {
        suffix = "mac-arm64";
        chromiumHash = "sha256-qXdgHeBS5IFIa4hZVmjq0+31v/uDPXHyc4aH7Wn2E7E=";
        headlessShellHash = "sha256-45DjMIu0t7IEYdXOmIqpV/1/MKdEfx/8T7DWagh6Zhc=";
      };
    };

    config = platformConfig.${system} or (throw "Unsupported system: ${system}");

    chromium-1208 = prev.fetchzip {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${chromiumVersion}/${config.suffix}/chrome-${config.suffix}.zip";
      hash = config.chromiumHash;
      stripRoot = false;
    };

    chromium-headless-shell-1208 = prev.fetchzip {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${chromiumVersion}/${config.suffix}/chrome-headless-shell-${config.suffix}.zip";
      hash = config.headlessShellHash;
      stripRoot = false;
    };

    originalBrowsers = prev.playwright-driver.browsers;
  in {
    playwright-driver =
      prev.playwright-driver
      // {
        browsers = prev.linkFarm "playwright-browsers" (
          (builtins.listToAttrs (
            map (name: {
              inherit name;
              value = "${originalBrowsers}/${name}";
            }) (builtins.attrNames (builtins.readDir originalBrowsers))
          ))
          // (prev.lib.optionalAttrs (config.chromiumHash != "") {
            "chromium-${revision}" = chromium-1208;
            "chromium_headless_shell-${revision}" = chromium-headless-shell-1208;
          })
        );
      };
  };
}
