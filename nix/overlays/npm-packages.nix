let
  lib = import ./lib.nix;
  inherit (lib) mkVendoredNpmPackage;
in {
  # secretlint - Secret linting tool
  # Uses custom package.json to bundle secretlint with rule preset
  # Renovate: datasource=npm depName=secretlint
  secretlint = mkVendoredNpmPackage {
    pname = "secretlint";
    version = "11.4.0";
    npmDepsHash = "sha256-aSqP/9qHe++tqRjWeKv5jTy2hHMx96oHHXsJCn+t3/o=";
    meta = {
      description = "Pluggable linting tool to prevent commit secret/credential file";
      homepage = "https://github.com/secretlint/secretlint";
    };
  };

  # textlint - Pluggable linting tool for text and markdown
  # Uses custom package.json to bundle textlint with Japanese writing preset
  # Renovate: datasource=npm depName=textlint
  textlint = mkVendoredNpmPackage {
    pname = "textlint";
    version = "15.5.2";
    npmDepsHash = "sha256-2yEMpMJbTe8tHm9bPFTyaWD4mIiJDRlBJBYAgslC6cg=";
    meta = {
      description = "Pluggable linting tool for text and markdown";
      homepage = "https://github.com/textlint/textlint";
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

  # unocss-language-server - UnoCSS LSP
  # Uses pre-built package from npm with vendored package-lock.json
  # Renovate: datasource=npm depName=unocss-language-server
  unocss-language-server = _final: prev: let
    version = "0.1.8";
    tarball = prev.fetchurl {
      url = "https://registry.npmjs.org/unocss-language-server/-/unocss-language-server-${version}.tgz";
      hash = "sha256-16xM1/6Um2FMj4i8Ua3uP7to2PiRX4Z8oDnUwnn232s=";
    };
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

      dontNpmBuild = true;

      meta = with prev.lib; {
        description = "Language server for UnoCSS";
        homepage = "https://github.com/xna00/unocss-language-server";
        license = licenses.mit;
        mainProgram = "unocss-language-server";
      };
    };
  };

  # takt - AI Agent orchestration framework
  # Uses pre-built package from npm with vendored package-lock.json
  # Renovate: datasource=npm depName=takt
  takt = _final: prev: let
    version = "0.33.2";
    tarball = prev.fetchurl {
      url = "https://registry.npmjs.org/takt/-/takt-${version}.tgz";
      hash = "sha256-JTfS70+05CSYtIUbFkkGhoPorXGHcoHMHeYBBf1OeGE=";
    };
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/takt/package-lock.json);
  in {
    takt = prev.buildNpmPackage {
      pname = "takt";
      inherit version;

      src = prev.runCommand "takt-src" {} ''
        mkdir -p $out
        tar -xzf ${tarball} -C $out --strip-components=1
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-z8YC2f5WDA8TrseXLTbeJr2QXGhJgDGzaDpyyHGujto=";

      dontNpmBuild = true;

      meta = with prev.lib; {
        description = "AI Agent orchestration framework";
        homepage = "https://github.com/nrslib/takt";
        license = licenses.mit;
        mainProgram = "takt";
      };
    };
  };
}
