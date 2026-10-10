# Codex の notify フック (名前の無いスレッドに codex-auto の app-server 経由で名前を付ける)。
# ソースは tools/codex-auto-title
# checkPhase で go test が走るので、`nix flake check` の home ビルドがテストを兼ねる
{
  codex-auto-title = _final: prev: {
    codex-auto-title = prev.buildGoModule {
      pname = "codex-auto-title";
      version = "0.1.0";

      src = ../../tools/codex-auto-title;

      # go.sum が変わったら (Renovate の gomod 更新を含む) 再計算する。
      # scripts/update-hashes.ts が go.sum の差分を検出して更新する。
      vendorHash = "sha256-InhrAen7gk+BBFgn22IzBodEUXy90RBOGNJaj1bo25s=";

      # scripts/test-codex-auto.sh が使う模擬 app-server はプロファイルに入れない
      excludedPackages = ["cmd/test-listener"];

      meta = {
        description = "Codex notify hook that names unnamed threads through the codex-auto app-server";
        mainProgram = "codex-auto-title";
      };
    };
  };
}
