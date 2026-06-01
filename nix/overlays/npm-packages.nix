{
  # unocss-language-server - UnoCSS LSP
  # Uses pre-built package from npm with vendored package-lock.json
  # Renovate: datasource=npm depName=unocss-language-server
  unocss-language-server = _final: prev: let
    version = "0.1.9";
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

      npmDepsHash = "sha256-6hm3UXxQrmS9nQzMjYGXrXVMkfi3pEdd0y6WY8KUFHA=";

      dontNpmBuild = true;

      meta = with prev.lib; {
        description = "Language server for UnoCSS";
        homepage = "https://github.com/xna00/unocss-language-server";
        license = licenses.mit;
        mainProgram = "unocss-language-server";
      };
    };
  };

  # vite-plus - Unified toolchain for the web (vp CLI)
  # vite-plus's tarball references private workspace packages in its own
  # devDependencies, so we cannot reuse its package.json directly. Instead we
  # vendor a minimal wrapper package.json + package-lock.json that depends on
  # vite-plus@<version>, then expose node_modules/vite-plus/bin/vp as $out/bin/vp.
  # Renovate: datasource=npm depName=vite-plus
  vite-plus = _final: prev: let
    version = "0.1.20";
    packageJson = prev.writeText "package.json" (builtins.readFile ../npm-locks/vite-plus/package.json);
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/vite-plus/package-lock.json);
  in {
    vite-plus = prev.buildNpmPackage {
      pname = "vite-plus";
      inherit version;

      src = prev.runCommand "vite-plus-src" {} ''
        mkdir -p $out
        cp ${packageJson} $out/package.json
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-gGL++lSnaH6gQVpUf/BxoVGN6ZG2USpfJ4LYn3g/J08=";
      npmFlags = ["--legacy-peer-deps"];
      dontNpmBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib $out/bin
        cp -r node_modules $out/lib/node_modules
        ln -s ../lib/node_modules/vite-plus/bin/vp $out/bin/vp
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "The Unified Toolchain for the Web";
        homepage = "https://github.com/voidzero-dev/vite-plus";
        license = licenses.mit;
        mainProgram = "vp";
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
      };
    };
  };
}
