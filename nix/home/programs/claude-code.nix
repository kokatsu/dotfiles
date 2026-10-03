{
  config,
  pkgs,
  lib,
  validDotfilesDir,
  ...
}: {
  # swap=0 の WSL では子プロセス 1 つの暴走が VM ごと落とす。全セッションを 1 つの slice に
  # まとめて上限を掛け、超過時はカーネルが slice 内の最大プロセスだけを OOM kill する。
  # OOMPolicy の既定 (stop) だと scope ごと止まり claude 本体も巻き添えになる
  home.packages =
    [pkgs.agent-guard]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      (lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
        exec systemd-run --user --scope --quiet --collect --slice=claude.slice \
          -p OOMPolicy=continue -- ${pkgs.claude-code}/bin/claude "$@"
      ''))
    ];

  systemd.user.slices = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    claude = {
      Unit.Description = "Claude Code sessions";
      Slice.MemoryMax = "16G";
    };
  };

  home.file = {
    # /effort などClaude Code自身の書き戻しを作業ツリーへ反映する。
    ".config/claude/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/claude/settings.json";
      force = true;
    };
    ".config/claude/CLAUDE.md".source = ../../../.config/claude/.CLAUDE.md;
    ".config/claude/skills".source = ../../../.config/claude/skills;
    ".config/claude/rules".source = ../../../.config/claude/rules;
    ".config/claude/file-suggestion.sh" = {
      source = ../../../.config/claude/file-suggestion.sh;
      executable = true;
    };
    ".config/claude/hooks/check-ai-writing.sh" = {
      source = ../../../.config/claude/hooks/check-ai-writing.sh;
      executable = true;
    };
    ".config/claude/hooks/gh-api-guard.sh" = {
      source = ../../../.config/claude/hooks/gh-api-guard.sh;
      executable = true;
    };
    ".config/claude/hooks/gh-api-guard.ts".source = ../../../.config/claude/hooks/gh-api-guard.ts;
    ".config/claude/hooks/herdr-cache-token.sh" = {
      source = ../../../.config/claude/hooks/herdr-cache-token.sh;
      executable = true;
    };
    ".config/claude/hooks/herdr-cache-token.ts".source = ../../../.config/claude/hooks/herdr-cache-token.ts;
    ".config/claude/hooks/shell-words.ts".source = ../../../.config/claude/hooks/shell-words.ts;
    ".config/claude/hooks/notify.sh" = {
      source = ../../../.config/claude/hooks/notify.sh;
      executable = true;
    };
    ".config/claude/hooks/transcript-grep-guard.sh" = {
      source = ../../../.config/claude/hooks/transcript-grep-guard.sh;
      executable = true;
    };
    ".config/claude/hooks/transcript-grep-guard.ts".source = ../../../.config/claude/hooks/transcript-grep-guard.ts;
    ".config/claude/hooks/textlint-response.json".source = ../../../.config/claude/hooks/textlint-response.json;
    ".config/claude/keybindings.json".text = builtins.toJSON {
      "$schema" = "https://platform.claude.com/docs/schemas/claude-code/keybindings.json";
      "$docs" = "https://code.claude.com/docs/en/keybindings";
      bindings = [
        {
          context = "Global";
          bindings = {
            "ctrl+t" = null;
            "alt+t" = "app:toggleTodos";
          };
        }
        {
          context = "Chat";
          bindings = {
            "ctrl+s" = null;
            "alt+shift+h" = "chat:stash";
          };
        }
      ];
    };
  };
}
