# Claude Code の Stop / SessionStart / PostCompact フック (prompt cache の失効時刻を Herdr に報告する)。
# ソースは tools/herdr-cache-token
# checkPhase で go test が走る。packages.nix の !isCI 側にあるので CI の home ビルドには入らず、
# CI では `just check-static` の herdr-cache-token-test がテストを担う
{
  herdr-cache-token = _final: prev: {
    herdr-cache-token = prev.buildGoModule {
      pname = "herdr-cache-token";
      version = "0.1.0";

      src = ../../tools/herdr-cache-token;

      # 標準ライブラリだけなので vendor するものがない
      vendorHash = null;

      meta = {
        description = "Claude Code hook that reports the prompt cache expiry to Herdr";
        mainProgram = "herdr-cache-token";
      };
    };
  };
}
