{
  # win32yank - Windows clipboard tool for WSL
  # Renovate: datasource=github-releases depName=equalsraf/win32yank
  win32yank = _final: prev: {
    win32yank = prev.stdenvNoCC.mkDerivation rec {
      pname = "win32yank";
      version = "0.1.1";

      src = prev.fetchzip {
        url = "https://github.com/equalsraf/win32yank/releases/download/v${version}/win32yank-x64.zip";
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
