{
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
}
