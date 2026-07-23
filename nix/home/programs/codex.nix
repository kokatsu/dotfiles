{
  pkgs,
  lib,
  config,
  validDotfilesDir,
  ...
}: {
  home.file = {
    # built-in skills (.system) を残すため、共有するskillだけを個別にリンクする。
    ".config/codex/skills/browser-research".source = ../../../.config/codex/skills/browser-research;

    # `herdr integration install codex` の生成物をNix管理する。
    ".config/codex/herdr-agent-state.sh" = {
      source = ../../../.config/codex/herdr-agent-state.sh;
      executable = true;
    };
    ".config/codex/hooks.json".text = builtins.toJSON {
      hooks.SessionStart = [
        {
          hooks = [
            {
              command = "bash '${config.xdg.configHome}/codex/herdr-agent-state.sh' session";
              timeout = 10;
              type = "command";
            }
          ];
        }
      ];
    };
  };

  # git管理の設定とCodex自身が書き戻すローカル状態をマージする。
  home.activation.mergeCodexConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
    CODEX_DIR="$HOME/.config/codex"
    BASE="${validDotfilesDir}/.config/codex/config.toml"
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
      $DRY_RUN_CMD cp "$BASE" "$TARGET"
      if [ -n "$LOCAL_STATE" ]; then
        if [ -n "$DRY_RUN_CMD" ]; then
          echo "Preserving Codex local state in $TARGET"
        else
          printf '\n%s\n' "$LOCAL_STATE" >> "$TARGET"
        fi
      fi
    else
      $DRY_RUN_CMD cp "$BASE" "$TARGET"
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
}
