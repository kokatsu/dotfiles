{
  config,
  pkgs,
  lib,
  dotfilesDir,
  ...
}: {
  # .devcontainer の Claude Code と Codex にホストと同じ設定とフックを渡す最小構成。
  # 設定を生成する module はホストと共有し、ホストの他の module は読まない
  imports = [
    ../home/catppuccin-palette.nix
    ../home/programs/claude-code.nix
    ../home/programs/codex.nix
    ../home/themes/claude-code.nix
  ];

  _module.args.validDotfilesDir = dotfilesDir;

  manual.manpages.enable = false;

  home = {
    username = "vscode";
    homeDirectory = "/home/vscode";
    stateVersion = "24.11";

    # settings.json と hooks.json が呼ぶコマンド
    packages = with pkgs; [
      agent-hooks
      cc-statusline
      fd
      jq
      textlint-with-rules
    ];

    file = {
      # ホストは herdr.nix が配置する
      ".config/herdr/hooks/report-agent-session.sh" = {
        source = ../../.config/herdr/hooks/report-agent-session.sh;
        executable = true;
      };
      # ホストと同じく作業ツリーへリンクすると、Claude Code が
      # --dangerously-skip-permissions の確認を省く設定をリポジトリへ書き戻すため、下でコピーする
      ".config/claude/settings.json".enable = lib.mkForce false;
    };

    activation.copyClaudeSettings =
      lib.hm.dag.entryAfter ["linkGeneration"]
      # bash
      ''
        TARGET="${config.xdg.configHome}/claude/settings.json"
        $DRY_RUN_CMD rm -f "$TARGET"
        if [ -z "$DRY_RUN_CMD" ]; then
          # ホストの /theme の選択はリポジトリの settings.json に無い。テーマの slug は
          # devcontainer.json がホストから渡す CC_STATUSLINE_THEME と同じ catppuccin-<flavor>
          ${pkgs.jq}/bin/jq '. + {skipDangerousModePermissionPrompt: true}
            + (env.CC_STATUSLINE_THEME | if . then {theme: "custom:\(.)"} else {} end)' \
            "${dotfilesDir}/.config/claude/settings.json" > "$TARGET"
        fi
      '';
  };

  xdg.enable = true;
}
