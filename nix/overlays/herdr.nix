# Herdr 公式リリースバイナリを pkgs.herdr として公開する。
# herdr-nix 自体は bin/herdr のみなので、nixpkgs 版から失われるシェル補完を補う。
{inputs}: {
  herdr = _final: prev: let
    # 上流 herdr-nix が v0.8.0 で止まっているため、追いつくまでこちらでリリース
    # バイナリを上書きする。上流が追随したら pinnedVersion/assets ごと削除する。
    # 更新: バージョンを上げたら nix-prefetch-url で hash を取り直す。
    pinnedVersion = "0.9.0";
    assets = {
      x86_64-linux = {
        name = "herdr-linux-x86_64";
        hash = "sha256-T6GgEVjdgEPaktMbJweAsNzBBgMDjZthysTYGrY/tx8=";
      };
      aarch64-linux = {
        name = "herdr-linux-aarch64";
        hash = "sha256-nI2yD7fnQnsTjVNnET8WIf/TGfL2XW8AniWUApEV8NI=";
      };
      aarch64-darwin = {
        name = "herdr-macos-aarch64";
        hash = "sha256-MrU98JhyYoBZx4mmnwKmuOKeFN3yZxFCHzRj9wwa7xc=";
      };
    };
    asset = assets.${prev.stdenv.hostPlatform.system};
    upstream = inputs.herdr-nix.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (_: {
      version = pinnedVersion;
      src = prev.fetchurl {
        url = "https://github.com/herdrdev/herdr/releases/download/v${pinnedVersion}/${asset.name}";
        inherit (asset) hash;
      };
    });
  in {
    herdr = prev.symlinkJoin {
      name = "herdr-${upstream.version}";
      pname = "herdr";
      inherit (upstream) version;
      paths = [upstream];
      nativeBuildInputs = [prev.installShellFiles];
      postBuild = prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
        completionDir=$(mktemp -d)

        generateCompletion() {
          shell=$1
          output=$2
          if ! "$out/bin/herdr" completion "$shell" >"$output"; then
            echo "herdr completion $shell failed" >&2
            return 1
          fi
          if [[ ! -s "$output" ]]; then
            echo "herdr completion $shell produced empty output" >&2
            return 1
          fi
        }

        generateCompletion bash "$completionDir/herdr.bash"
        generateCompletion fish "$completionDir/herdr.fish"
        generateCompletion zsh "$completionDir/_herdr"

        installShellCompletion --cmd herdr \
          --bash "$completionDir/herdr.bash" \
          --fish "$completionDir/herdr.fish" \
          --zsh "$completionDir/_herdr"
      '';
      inherit (upstream) meta;
      passthru = (upstream.passthru or {}) // {unwrapped = upstream;};
    };
  };
}
