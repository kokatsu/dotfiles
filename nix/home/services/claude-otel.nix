{
  config,
  pkgs,
  lib,
  isWSL,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  stateDir = "${config.home.homeDirectory}/.local/state/claude-otel";

  # 127.0.0.1:4318 で OTLP/HTTP JSON を受け、api_request の 5 項目だけを追記する。
  # user.email などほかの属性とイベントは保存しない
  receiver = pkgs.writeText "claude-otel-recv.py" ''
    import http.server, json, os, sys

    os.umask(0o077)
    out = sys.argv[1]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    # launchd が StandardErrorPath のために先に既定の権限で作ることがある
    os.chmod(os.path.dirname(out), 0o700)
    keep = ("event.timestamp", "session.id", "query_source", "model", "cost_usd")
    max_body = 16 * 1024 * 1024

    class H(http.server.BaseHTTPRequestHandler):
        # 止まった接続をこの秒数で打ち切り、stderr に "Request timed out" を残す
        timeout = 10

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            if n > max_body:
                self.send_error(413)
                return
            try:
                recs = [r for rl in json.loads(self.rfile.read(n)).get("resourceLogs", [])
                        for sl in rl.get("scopeLogs", []) for r in sl.get("logRecords", [])]
            except ValueError:
                recs = []
            with open(out, "a") as f:
                for r in recs:
                    a = {x["key"]: next(iter(x["value"].values()), None) for x in r.get("attributes", [])}
                    if a.get("event.name") == "api_request":
                        f.write(json.dumps({k: a.get(k) for k in keep}) + "\n")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b"{}")

        # 成功したリクエストだけ黙らせる。エラーとタイムアウトは stderr に出る
        def log_request(self, *a):
            pass

    http.server.HTTPServer(("127.0.0.1", 4318), H).serve_forever()
  '';
  cmd = ["${pkgs.python3}/bin/python3" "${receiver}" "${stateDir}/api_request.jsonl"];
in
  lib.mkMerge [
    (lib.mkIf isDarwin {
      launchd.agents.claude-otel = {
        enable = true;
        config = {
          ProgramArguments = cmd;
          RunAtLoad = true;
          KeepAlive = true;
          ProcessType = "Background";
          StandardErrorPath = "${stateDir}/recv.err.log";
        };
      };
    })
    (lib.mkIf isWSL {
      systemd.user.services.claude-otel = {
        Unit.Description = "Receive Claude Code OTel api_request logs";
        Service = {
          ExecStart = lib.escapeShellArgs cmd;
          Restart = "always";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ]
