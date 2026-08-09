{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in
  lib.mkIf (!isDarwin) {
    systemd.user.services.feed-watch = {
      Unit = {
        Description = "Check GitHub feeds for new commits";
      };
      Service = {
        Type = "oneshot";
        # systemd user unit は home.sessionVariables を引き継がないため、
        # claude -p が ~/.claude を config dir と誤認して認証に失敗する
        Environment = "CLAUDE_CONFIG_DIR=${config.xdg.configHome}/claude";
        ExecStart = toString (pkgs.writeShellScript "feed-watch-check" ''
          # bash は feed-watch / feed-summarize の shebang (#!/usr/bin/env bash) 解決に必要
          export PATH="${lib.makeBinPath (with pkgs; [bash gh jq curl coreutils gnused gnugrep gawk python3 agent-browser claude-code])}"
          "$HOME/.local/bin/scripts/feed-watch" check
          exec "$HOME/.local/bin/scripts/feed-summarize"
        '');
      };
    };

    systemd.user.timers.feed-watch = {
      Unit = {
        Description = "Check GitHub feeds every hour";
      };
      Timer = {
        OnCalendar = "hourly";
        Persistent = true;
      };
      Install = {
        WantedBy = ["timers.target"];
      };
    };
  }
