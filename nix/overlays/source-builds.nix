let
  inherit (import ./lib.nix) guardEqual;
in {
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

  # mermaid-ascii - Render Mermaid graphs as ASCII/Unicode text
  # Renovate: datasource=github-releases depName=AlexanderGrooff/mermaid-ascii
  mermaid-ascii = _final: prev: {
    mermaid-ascii = prev.buildGoModule rec {
      pname = "mermaid-ascii";
      version = "1.6.1";

      src = prev.fetchFromGitHub {
        owner = "AlexanderGrooff";
        repo = "mermaid-ascii";
        rev = version;
        hash = "sha256-KYCJIgLwjJR5RM1AdGrV47UhFgpLqwro42E54pzhYWE=";
      };

      vendorHash = "sha256-S/K6W8KC6YzwZPioucoiwOMd29LPv0J22T3MS0X+W5g=";

      meta = with prev.lib; {
        description = "Render Mermaid graphs as ASCII/Unicode text";
        homepage = "https://github.com/AlexanderGrooff/mermaid-ascii";
        license = licenses.mit;
        mainProgram = "mermaid-ascii";
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

      # v1.2.1のTestFormatSingleValidationErrorはvalidator依存の変化に追従できず、
      # expected messageに対してnilを返して失敗する。他のGo testは維持する。
      # version更新時はskipを外して再確認すること。
      checkFlags =
        guardEqual
        "x-api-playground version"
        "1.2.1"
        version
        ["-skip=TestFormatSingleValidationError"];

      meta = with prev.lib; {
        description = "Local HTTP server that simulates X API v2 for testing";
        homepage = "https://github.com/xdevplatform/playground";
        license = licenses.mit;
        mainProgram = "playground";
      };
    };
  };
}
