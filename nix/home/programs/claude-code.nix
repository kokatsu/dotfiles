{
  config,
  pkgs,
  lib,
  validDotfilesDir,
  isDevcontainer,
  ...
}: let
  # devcontainer には systemd が無い
  useSlice = pkgs.stdenv.hostPlatform.isLinux && !isDevcontainer;
in {
  # swap=0 の WSL では子プロセス 1 つの暴走が VM ごと落とす。全セッションを 1 つの slice に
  # まとめて上限を掛け、超過時はカーネルが slice 内の最大プロセスだけを OOM kill する。
  # OOMPolicy の既定 (stop) だと scope ごと止まり claude 本体も巻き添えになる
  home.packages = lib.optionals useSlice [
    (lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
      PATH=${pkgs.wl-clipboard}/bin:$PATH exec systemd-run --user --scope --quiet --collect --slice=claude.slice \
        -p OOMPolicy=continue -- ${pkgs.claude-code}/bin/claude "$@"
    ''))
  ];

  systemd.user.slices = lib.mkIf useSlice {
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
    # Claude Code が型定義と tsconfig.json を mod フォルダへ書き込むため、store ではなく作業ツリーを指す
    ".config/claude/mods".source = config.lib.file.mkOutOfStoreSymlink "${validDotfilesDir}/.config/claude/mods";
    # Claude Code は bridge-spawn などを CLAUDE_CONFIG_DIR ではなく homedir 直下の .claude に書くため、
    # 同じディレクトリへ寄せる
    ".claude".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";
    ".config/claude/CLAUDE.md".source = ../../../.config/claude/.CLAUDE.md;
    ".config/claude/skills".source = ../../../.config/claude/skills;
    ".config/claude/rules".source = ../../../.config/claude/rules;
    ".config/claude/file-suggestion.sh" = {
      source = ../../../.config/claude/file-suggestion.sh;
      executable = true;
    };
    ".config/claude/hooks/herdr-cache-token.sh" = {
      source = ../../../.config/claude/hooks/herdr-cache-token.sh;
      executable = true;
    };
    ".config/claude/hooks/notify.sh" = {
      source = ../../../.config/claude/hooks/notify.sh;
      executable = true;
    };
    ".config/claude/keybindings.json".text = builtins.toJSON {
      "$schema" = "https://platform.claude.com/docs/schemas/claude-code/keybindings.json";
      "$docs" = "https://code.claude.com/docs/en/keybindings";
      bindings = [
        {
          context = "Chat";
          bindings = {
            "ctrl+s" = null;
            "alt+q" = "chat:stash";
          };
        }
      ];
    };
  };
}
