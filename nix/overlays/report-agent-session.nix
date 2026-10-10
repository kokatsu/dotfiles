# Claude Code / Codex の SessionStart フック (セッション ID を Herdr に報告する)。
# ソースは tools/report-agent-session
# checkPhase で go test が走るので、`nix flake check` の home ビルドが報告条件のテストを兼ねる
{
  report-agent-session = _final: prev: {
    report-agent-session = prev.buildGoModule {
      pname = "report-agent-session";
      version = "0.1.0";

      src = ../../tools/report-agent-session;

      # 標準ライブラリだけなので vendor するものがない
      vendorHash = null;

      meta = {
        description = "SessionStart hook that reports Claude Code and Codex sessions to Herdr";
        mainProgram = "report-agent-session";
      };
    };
  };
}
