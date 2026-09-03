{
  pkgs,
  lib,
  isWSL,
  ...
}:
lib.mkIf isWSL {
  systemd.user.services.status-watch = {
    Unit = {
      Description = "Check Claude and OpenAI status for the WezTerm status bar";
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "status-watch-check" ''
        export PATH="${lib.makeBinPath (with pkgs; [bash coreutils curl jq])}"
        exec "$HOME/.local/bin/scripts/status-watch" check
      '');
    };
  };

  systemd.user.timers.status-watch = {
    Unit = {
      Description = "Check Claude and OpenAI status every 5 minutes";
    };
    Timer = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
