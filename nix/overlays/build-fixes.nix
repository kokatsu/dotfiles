{
  # Pin vue-language-server to 3.0.8
  # fetcherVersion 3 normalizes permissions and packs a reproducible tarball,
  # so the pnpmDeps hash is platform-independent (no separate darwin/linux
  # hashes needed).
  vue-language-server-pin = _final: prev: {
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
        pnpm = prev.pnpm_10;
        fetcherVersion = 3;
        hash = "sha256-ITZ4GD03U3hprUbt60MG9vi1G8+8u421x5QC6YvU11w=";
      };
    });
  };

  # Fix cava build on aarch64-darwin
  # iniparser's dependency unity-test has C++ compilation issues with new clang
  cava-darwin-fix = _final: prev: {
    iniparser = prev.iniparser.overrideAttrs (_old: {
      doCheck = false;
    });
  };

  # direnv 2.37.1 zsh checkPhase hangs on macOS Nix sandbox
  # (SIGCHLD race in waitforpid during $(direnv export zsh))
  direnv-no-check = _final: prev: {
    direnv = prev.direnv.overrideAttrs (_old: {
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
      # branch: perf/optimize-graph-construction
      rev = "2781f5305c8d46c6dda0e7c71d4238954887f5d9";
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

  # pipx 1.8.0 test_package_specifier tests fail with newer `packaging`,
  # which normalizes PEP 508 direct references to `name @ url` (space around
  # `@`) while the tests still assert the old `name@ url` form. Test-only
  # formatting drift; pipx itself works fine. Disable via pythonPackagesExtensions
  # because top-level `pipx` is `toPythonApplication python3Packages.pipx`,
  # and the tests run through pytestCheckHook (not the `doCheck` gate).
  pipx-no-check = _final: prev: {
    pythonPackagesExtensions =
      (prev.pythonPackagesExtensions or [])
      ++ [
        (_pyfinal: pyprev: {
          pipx = pyprev.pipx.overrideAttrs (old: {
            disabledTests =
              (old.disabledTests or [])
              ++ [
                "test_fix_package_name"
                "test_parse_specifier_for_metadata"
              ];
          });
        })
      ];
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
}
