{
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

      doCheck = false;

      meta = with prev.lib; {
        description = "Local HTTP server that simulates X API v2 for testing";
        homepage = "https://github.com/xdevplatform/playground";
        license = licenses.mit;
        mainProgram = "playground";
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

  daily = _final: prev: {
    daily = prev.stdenvNoCC.mkDerivation {
      pname = "daily";
      version = "0.1.0";
      src = ../../tools/daily;
      nativeBuildInputs = [prev.zig];
      dontConfigure = true;
      dontFixup = true;
      buildPhase = ''
        export HOME=$TMPDIR
        export XDG_CACHE_HOME=$TMPDIR/.cache
        zig build -Doptimize=ReleaseFast --prefix $out
      '';
    };
  };
}
