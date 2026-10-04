# Claude Code / Codex の PreToolUse フック (Bash の禁止コマンドと Herdr 入力、
# Edit/Write の Home Manager 管理下パス)。ソースは tools/agent-guard
# checkPhase で go test が走るので、`nix flake check` の home ビルドが判定のテストを兼ねる
{
  agent-guard = _final: prev: {
    agent-guard = prev.buildGoModule {
      pname = "agent-guard";
      version = "0.1.0";

      src = ../../tools/agent-guard;

      # go.sum が変わったら (Renovate の gomod 更新を含む) 再計算する。
      # scripts/update-hashes.ts が go.sum の差分を検出して更新する。
      vendorHash = "sha256-gD/21H1aujRzrvSq6RfrKrzujDHn0eG4ctDqYICSr0s=";

      # check-regex-dialect.sh が go run する補助ツールはプロファイルに入れない
      excludedPackages = ["cmd/regex-dialect"];

      meta = {
        description = "PreToolUse hook that blocks banned commands and edits to managed paths";
        mainProgram = "agent-guard";
      };
    };
  };
}
