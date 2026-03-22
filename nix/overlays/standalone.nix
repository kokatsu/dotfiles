{
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

  # agent-browser - Browser automation agent
  # Uses pre-built native binaries from npm package
  # Renovate: datasource=npm depName=agent-browser
  agent-browser = final: prev: let
    version = "0.21.4";
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/agent-browser/package-lock.json);
  in {
    agent-browser = prev.buildNpmPackage {
      pname = "agent-browser";
      inherit version;

      src = prev.fetchurl {
        url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
        hash = "sha256-4fs+SUczp7W8n6nxmANTT0FYGD0iTmy6qFRSGUSgh8A=";
      };

      npmDepsHash = "sha256-6Qtj2jenInza780Nc1c/5ESSJxbX8ssgHqclPV20m9E=";
      dontNpmBuild = true;
      npmPackFlags = ["--ignore-scripts"];
      npmFlags = ["--ignore-scripts" "--legacy-peer-deps"];

      PLAYWRIGHT_BROWSERS_PATH = final.playwright-driver.browsers;

      nativeBuildInputs = [prev.makeWrapper];

      postPatch = ''
        cp ${packageLock} package-lock.json
      '';

      postInstall = ''
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

  # k1LoW/deck - Markdown to Google Slides
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=k1LoW/deck
  deck = _final: prev: let
    version = "1.23.1";
    hashes = {
      "aarch64-darwin" = "sha256-+ot2Ur1X6RFxTy7vgPYqFR+WKotqNp+lTCmOLuKGBXE=";
      "x86_64-darwin" = "sha256-l7vstvf8UZyDT5Hf4Irf5M3QtKVl7Zegg/ziw4IOFTs=";
      "aarch64-linux" = "sha256-h+MdFTV4h17mHDBw613CGyMr0uBFdfJNzjfs7bfmE/A=";
      "x86_64-linux" = "sha256-3fw6KzyNZeLvWzcq358oHvDrT7or3NRz6HhGfGJ5f5o=";
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
}
