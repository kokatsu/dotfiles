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
}
