# Claude Code / Codex の PreToolUse (Bash) フック。ソースは tools/agent-guard
# checkPhase で go test が走るので、`nix flake check` の home ビルドが判定のテストを兼ねる
{
  agent-guard = _final: prev: {
    agent-guard = prev.buildGoModule {
      pname = "agent-guard";
      version = "0.1.0";

      src = ../../tools/agent-guard;

      # go.sum が変わったら (Renovate の gomod 更新を含む) 再計算する。
      # pr.yml の vendorHash 自動更新はこのパッケージを対象にしていない
      vendorHash = "sha256-gD/21H1aujRzrvSq6RfrKrzujDHn0eG4ctDqYICSr0s=";

      # check-regex-dialect.sh が go run する補助ツールはプロファイルに入れない
      excludedPackages = ["cmd/regex-dialect"];

      meta = {
        description = "PreToolUse hook that blocks banned Bash commands";
        mainProgram = "agent-guard";
      };
    };
  };
}
