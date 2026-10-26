{
  pkgs,
  config,
  plainConfig,
}: let
  inherit (pkgs) lib;
  # check 経路と共通処理が PATH から呼ぶ外部コマンド。
  commands = {
    disk-watch = "awk bash date df dirname jq mkdir mktemp mv readlink rm tr uname";
    feed-watch = "bash cat curl deno dirname flock gh jq mkdir mktemp mv readlink rm sleep tr uname yq";
    status-watch = "bash curl date dirname jq mkdir mktemp mv readlink rm tr uname";
  };
  probe = pkgs.writeShellScript "watch-probe" ''
    set -euo pipefail
    [[ $# -eq 1 && $1 == check ]]
    for command in $CHECK_COMMANDS; do
      command -v "$command" >/dev/null
    done
  '';
  checkWatch = name: requiredCommands: let
    service = config.systemd.user.services.${name};
    command = lib.head service.Service.ExecStart;
    unit = config.xdg.configFile."systemd/user/${name}.service".source;
    timer = config.xdg.configFile."systemd/user/${name}.timer".source;
  in
    assert lib.length service.Service.ExecStart == 1; ''
      grep -Fx 'Type=oneshot' ${unit}
      grep -Fx 'ExecStart=${command}' ${unit}
      grep -Fx 'OnCalendar=*:0/5' ${timer}
      grep -Fx 'Persistent=true' ${timer}
      grep -Fx 'WantedBy=timers.target' ${timer}
      ln -s ${probe} "$testHome/.local/bin/scripts/${name}"
      env -i HOME="$testHome" CHECK_COMMANDS=${lib.escapeShellArg requiredCommands} ${command}
    '';
in
  assert lib.assertMsg
  (lib.all (name: !(builtins.hasAttr name plainConfig.systemd.user.services)) (builtins.attrNames commands ++ ["claude-otel" "devcontainer-transcripts"]))
  "WSL services must not be enabled on ordinary Linux";
    pkgs.runCommand "wsl-services-check" {} ''
      testHome="$TMPDIR/home"
      mkdir -p "$testHome/.local/bin/scripts"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList checkWatch commands)}
      grep -Fx 'TimeoutStartSec=10min' ${config.xdg.configFile."systemd/user/feed-watch.service".source}
      grep -Fx 'OnCalendar=minutely' ${config.xdg.configFile."systemd/user/devcontainer-transcripts.timer".source}
      grep -Fx 'Restart=always' ${config.xdg.configFile."systemd/user/claude-otel.service".source}
      grep -Fx 'WantedBy=default.target' ${config.xdg.configFile."systemd/user/claude-otel.service".source}
      touch "$out"
    ''
