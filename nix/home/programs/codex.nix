{
  pkgs,
  lib,
  config,
  validDotfilesDir,
  ...
}: let
  baseConfig = (pkgs.formats.toml {}).generate "codex-config.toml" {
    approval_policy = "on-request";
    check_for_update_on_startup = false;
    file_opener = "none";
    model = "gpt-6.1-sol";
    model_reasoning_effort = "medium";
    model_verbosity = "low";
    plan_mode_reasoning_effort = "xhigh";
    project_doc_fallback_filenames = [
      "CLAUDE.md"
    ];
    sandbox_mode = "workspace-write";
    web_search = "cached";
    features = {
      hooks = true;
      memories = true;
      shell_snapshot = true;
    };
    history = {
      max_bytes = 104857600;
    };
    mcp_servers = {
      openaiDeveloperDocs = {
        url = "https://developers.openai.com/mcp";
      };
    };
    memories = {
      disable_on_external_context = true;
      min_rate_limit_remaining_percent = 25;
    };
    sandbox_workspace_write = {
      network_access = false;
      writable_roots = ["${config.xdg.dataHome}/Trash"];
    };
    shell_environment_policy = {
      ignore_default_excludes = false;
    };
    tools = {
      web_search = {
        context_size = "medium";
        location = {
          country = "JP";
          timezone = "Asia/Tokyo";
        };
      };
    };
    tui = {
      notifications = true;
      notification_condition = "always";
      resume_cwd = "session";
      terminal_title = [
        "thread"
      ];
      status_line = [
        "model-with-reasoning"
        "current-dir"
        "git-branch"
        "five-hour-limit"
        "weekly-limit"
        "codex-version"
      ];
    };
  };
  codexAuto = pkgs.writeShellApplication {
    name = "codex-auto";
    runtimeInputs = [
      pkgs.codex
      pkgs.coreutils
      pkgs.codex-auto-title
    ];
    text = builtins.readFile ../../../scripts/codex-auto.sh;
  };
in {
  home = {
    packages = [
      codexAuto
      pkgs.codex-auto-title
    ];

    file = {
      ".config/codex/AGENTS.md".source = ../../../.config/codex/.AGENTS.md;

      # ペットを有効にするとTUIがKitty graphicsのスプライトをアイドル中も
      # 描き続け、herdr serverが全ペインの出力を端末エミュレートするCPUに
      # 直撃してペイン切替が詰まる。config.tomlのtui.petは未設定のままにする。
      # Codex CLI 0.149.0向けの9行スプライト版。
      ".config/codex/pets/kometa-cli" = {
        source = ../../../.config/codex/pets/kometa-cli;
      };

      # Codex CLI とデスクトップアプリで共有するカスタムペット。
      ".config/codex/pets/kometa" = {
        source = ../../../.config/codex/pets/kometa;
      };

      # built-in skills (.system) を残すため、共有するskillだけを個別にリンクする。
      ".config/codex/skills/browser-research".source = ../../../.config/codex/skills/browser-research;
      ".config/codex/skills/herdr-peer".source = ../../../.config/codex/skills/herdr-peer;

      ".config/codex/check-ai-writing.sh" = {
        source = ../../../.config/claude/hooks/check-ai-writing.sh;
        executable = true;
      };
      ".config/codex/hooks.json".text = builtins.toJSON {
        hooks = {
          PostToolUse = [
            {
              matcher = "^apply_patch$";
              hooks = [
                {
                  command = "bash '${config.xdg.configHome}/codex/check-ai-writing.sh'";
                  timeout = 15;
                  type = "command";
                }
              ];
            }
          ];
          PreToolUse = [
            {
              matcher = "^Bash$";
              hooks = [
                {
                  command = "'${config.home.profileDirectory}/bin/agent-guard' codex";
                  type = "command";
                }
              ];
            }
          ];
          SessionStart = [
            {
              hooks = [
                {
                  # herdr.nix が配置する共有フック (Claude Code 側と同じ実装)。
                  command = "bash '${config.xdg.configHome}/herdr/hooks/report-agent-session.sh' session codex";
                  timeout = 10;
                  type = "command";
                }
              ];
            }
          ];
        };
      };
    };

    # git管理の設定とCodex自身が書き戻すローカル状態をマージする。
    activation.mergeCodexConfig =
      lib.hm.dag.entryAfter ["linkGeneration"]
      # bash
      ''
        CODEX_DIR="$HOME/.config/codex"
        BASE="${baseConfig}"
        TARGET="$CODEX_DIR/config.toml"
        $DRY_RUN_CMD mkdir -p "$CODEX_DIR"
        if [ -f "$TARGET" ]; then
          # セクション順に依存せず、Codexが管理するローカル状態だけを抽出する。
          LOCAL_STATE=$(${pkgs.gawk}/bin/awk '
            /^\[\[?/ {
              keep = 0
              if ($0 ~ /^\[\[?projects(\.|\])/) keep = 1
              if ($0 ~ /^\[\[?tui\.model_availability_nux\]\]?$/) keep = 1
              if ($0 ~ /^\[\[?notice(\.|\])/) keep = 1
              if ($0 ~ /^\[\[?hooks\.state(\.|\])/) keep = 1
            }
            keep { print }
          ' "$TARGET")
          TMP="$TARGET.tmp"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 600 "$BASE" "$TMP"
          if [ -n "$LOCAL_STATE" ]; then
            if [ -n "$DRY_RUN_CMD" ]; then
              echo "Preserving Codex local state in $TARGET"
            else
              printf '\n%s\n' "$LOCAL_STATE" >> "$TMP"
            fi
          fi
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv -f "$TMP" "$TARGET"
        else
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 600 "$BASE" "$TARGET"
        fi

        RULES_DIR="$CODEX_DIR/rules"
        RULES_BASE="${validDotfilesDir}/.config/codex/rules/managed.rules"
        RULES_TARGET="$RULES_DIR/managed.rules"
        LOCAL_RULES_TARGET="$RULES_DIR/default.rules"
        $DRY_RUN_CMD mkdir -p "$RULES_DIR"

        # 旧構成の管理ルールをdefault.rulesから取り除き、Codexが追記した
        # 1行形式のローカル許可だけを初回移行時に残す。
        if [ -f "$LOCAL_RULES_TARGET" ] && \
          [ "$(${pkgs.coreutils}/bin/head -n 1 "$LOCAL_RULES_TARGET")" = "# Read-only git inspection commands." ]; then
          LOCAL_RULES=$(${pkgs.gnugrep}/bin/grep '^prefix_rule(pattern=' "$LOCAL_RULES_TARGET" || true)
          if [ -n "$DRY_RUN_CMD" ]; then
            echo "Migrating Codex-local rules in $LOCAL_RULES_TARGET"
          elif [ -n "$LOCAL_RULES" ]; then
            printf '%s\n' "$LOCAL_RULES" > "$LOCAL_RULES_TARGET"
          else
            ${pkgs.coreutils}/bin/rm -f "$LOCAL_RULES_TARGET"
          fi
        fi

        $DRY_RUN_CMD cp "$RULES_BASE" "$RULES_TARGET"
      '';
  };
}
