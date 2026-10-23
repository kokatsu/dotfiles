# 公式のソースビルドに prefix バーとフォーカス枠の描画パッチ、シェル補完を追加する。
{inputs}: {
  herdr = _final: prev: let
    upstream = inputs.herdr-src.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      patches =
        (old.patches or [])
        ++ [
          ./patches/herdr-prefix-bar.patch
          ./patches/herdr-heavy-focus-border.patch
        ];
    });
  in {
    herdr = prev.symlinkJoin {
      name = "herdr-${upstream.version}";
      pname = "herdr";
      inherit (upstream) version;
      paths = [upstream];
      nativeBuildInputs = [prev.installShellFiles];
      postBuild =
        prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform)
        # bash
        ''
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
