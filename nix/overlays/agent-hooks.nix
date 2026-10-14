# Claude Code / Codex のフック。ソースは tools/agent-hooks (1 つの Go モジュール)。
# - agent-guard: PreToolUse で禁止コマンドと Herdr 入力、Home Manager 管理下パスの編集を止め、
#   Claude Code の読み取り専用の gh api を自動許可する
# - herdr-cache-token: Stop / SessionStart / PostCompact で prompt cache の失効時刻を Herdr に報告する
# - report-agent-session: SessionStart でセッション ID を、Codex のターン開始・終了で状態を Herdr に報告する
# checkPhase で go test が走るので、`nix flake check` の home ビルドがテストを兼ねる
{
  agent-hooks = _final: prev: {
    agent-hooks = prev.buildGoModule {
      pname = "agent-hooks";
      version = "0.1.0";

      src = ../../tools/agent-hooks;

      # go.sum が変わったら (Renovate の gomod 更新を含む) 再計算する。
      # scripts/update-hashes.ts が go.sum の差分を検出して更新する。
      vendorHash = "sha256-gD/21H1aujRzrvSq6RfrKrzujDHn0eG4ctDqYICSr0s=";

      # check-regex-dialect.sh が go run する補助ツールはプロファイルに入れない
      excludedPackages = ["cmd/regex-dialect"];

      # report-agent-session は Codex の pane 確認で ps を PATH から探し、そのテストも実際に ps を走らせる
      nativeCheckInputs = [prev.ps];

      meta.description = "Claude Code and Codex hooks: command guard, Codex thread naming, and Herdr session, Codex turn state and cache reports";
    };
  };
}
