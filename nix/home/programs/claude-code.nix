{
  config,
  validDotfilesDir,
  ...
}: {
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
    ".config/claude/hooks/banned-commands.json".source = ../../../.config/claude/hooks/banned-commands.json;
    ".config/claude/hooks/check-banned-commands.sh" = {
      source = ../../../.config/claude/hooks/check-banned-commands.sh;
      executable = true;
    };
    ".config/claude/hooks/check-managed-paths.sh" = {
      source = ../../../.config/claude/hooks/check-managed-paths.sh;
      executable = true;
    };
    ".config/claude/hooks/gh-api-guard.sh" = {
      source = ../../../.config/claude/hooks/gh-api-guard.sh;
      executable = true;
    };
    ".config/claude/hooks/herdr-agent-state.sh" = {
      source = ../../../.config/claude/hooks/herdr-agent-state.sh;
      executable = true;
    };
    ".config/claude/hooks/notify.sh" = {
      source = ../../../.config/claude/hooks/notify.sh;
      executable = true;
    };
    ".config/claude/keybindings.json".source = ../../../.config/claude/keybindings.json;
  };
}
