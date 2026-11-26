{
  config,
  lib,
  pkgs,
  validDotfilesDir,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  inherit (config.lib.file) mkOutOfStoreSymlink;

  # リポジトリを直接参照していて、switch を挟まず隔離の外で実行されるもの
  livePaths = [
    ".config/claude"
    ".config/herdr/plugins"
    ".config/nvim"
    ".config/wezterm"
    ".config/zsh/config.d"
    ".config/zsh/functions.d"
    "bin"
  ];
  # 親ディレクトリの rename による差し替えも防ぐ
  liveParents = lib.unique (lib.concatMap (path: let
    parts = lib.init (lib.splitString "/" path);
  in
    lib.genList (n: lib.concatStringsSep "/" (lib.take (n + 1) parts)) (lib.length parts))
  livePaths);

  mkProfile = {
    name,
    allow,
    read ? [],
    readFile ? [],
    allowDomain,
  }:
    builtins.toJSON {
      extends = "default";
      meta = {
        inherit name;
        version = "1.0.0";
      };
      groups.include = [
        "node_runtime"
        "rust_runtime"
        "python_runtime"
        "nix_runtime"
        "git_config"
        {
          name = "linux_sysfs_read";
          when = "linux";
        }
        "unlink_protection"
      ];
      security = {
        signal_mode = "isolated";
        ipc_mode = "shared_memory_only";
      };
      filesystem = {
        inherit allow read;
        read_file = readFile;
      };
      network.allow_domain = allowDomain;
      workdir.access = "readwrite";
      # Linux では nono-agent.sh が bwrap で同じものを保護する
      unsafe_macos_seatbelt_rules = lib.optionals isDarwin ([
          ''(deny file-write* (regex #"/\.git$"))''
          ''(deny file-write* (regex #"/\.git/(hooks(/|$)|(config|config\.worktree|commondir)$)"))''
          ''(deny file-write* (regex #"/\.git/modules(/|$)"))''
          ''(deny file-write* (regex #"/\.(claude|codex)(/|$)"))''
          ''(deny file-write* (regex #"/\.?lefthook(-local)?\.(ya?ml|toml|jsonc?)$"))''
        ]
        ++ map (path: ''(deny file-write* (subpath "${validDotfilesDir}/${path}"))'') livePaths
        ++ map (path: ''(deny file-write* (literal "${validDotfilesDir}/${path}"))'') liveParents);
    };
in {
  xdg.configFile = {
    "nono/config.toml".text =
      # toml
      ''
        [updates]
        check = false
      '';
    "nono/profiles/nono-agent-claude.json".text = mkProfile {
      name = "nono-agent-claude";
      allow = ["$HOME/.local/share/nono-agent/claude"];
      read = [
        "$HOME/.config/claude/themes"
        "${validDotfilesDir}/.config/claude/mods"
      ];
      readFile = ["${validDotfilesDir}/.config/claude/settings.json"];
      allowDomain = [
        "api.anthropic.com"
        "claude.ai"
        "claude.com"
        "platform.claude.com"
      ];
    };
    "nono/profiles/nono-agent-codex.json".text = mkProfile {
      name = "nono-agent-codex";
      allow = ["$HOME/.local/share/nono-agent/codex"];
      allowDomain = [
        "api.openai.com"
        "auth.openai.com"
        "chatgpt.com"
        "developers.openai.com"
      ];
    };
  };

  # 会話やログイン情報を普段の設定ディレクトリと分け、設定だけを共有する
  xdg.dataFile = {
    "nono-agent/claude/settings.json".source = mkOutOfStoreSymlink "${validDotfilesDir}/.config/claude/settings.json";
    "nono-agent/claude/CLAUDE.md".source = ../../../.config/claude/.CLAUDE.md;
    "nono-agent/claude/rules".source = ../../../.config/claude/rules;
    "nono-agent/claude/skills".source = ../../../.config/claude/skills;
    "nono-agent/claude/themes".source = mkOutOfStoreSymlink "${config.xdg.configHome}/claude/themes";
    "nono-agent/codex/AGENTS.md".source = config.home.file.".config/codex/AGENTS.md".source;
    "nono-agent/codex/pstack-adapter.md".source = config.home.file.".config/codex/pstack-adapter.md".source;
    "nono-agent/codex/hooks.json".text = config.home.file.".config/codex/hooks.json".text;
  };

  home.packages = [
    (pkgs.writeShellApplication {
      name = "nono-agent";
      runtimeInputs = [pkgs.coreutils pkgs.git pkgs.nono] ++ lib.optionals isLinux [pkgs.bubblewrap pkgs.findutils pkgs.gnused pkgs.perl pkgs.util-linux];
      runtimeEnv = {
        NONO_AGENT_CLAUDE = lib.getExe pkgs.claude-code;
        NONO_AGENT_CODEX = lib.getExe pkgs.codex;
        NONO_AGENT_WATCH = "${../../../scripts/nono-agent-watch.pl}";
        NONO_AGENT_DOTFILES = validDotfilesDir;
        NONO_AGENT_LIVE_PATHS = lib.concatStringsSep " " livePaths;
      };
      text = builtins.readFile ../../../scripts/nono-agent.sh;
    })
  ];
}
