{
  config,
  pkgs,
  lib,
  isWSL,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  stateDir = "${config.home.homeDirectory}/.local/state/claude-otel";
  port = 4318;

  # 127.0.0.1:port で OTLP/HTTP JSON を受け、下の keep に挙げたイベントと属性だけを
  # <event>.jsonl に追記する。user.email やツールの入力などほかの属性とイベントは保存しない
  receiver = pkgs.writeText "claude-otel-recv.py" ''
    import http.server, json, os, sys

    os.umask(0o077)
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    # launchd が StandardErrorPath のために先に既定の権限で作ることがある
    os.chmod(out, 0o700)
    common = ("event.timestamp", "session.id", "prompt.id", "deployment.environment",
              "query_source", "model", "effort", "duration_ms")
    keep = {
        "api_request": common + (
            "cost_usd", "input_tokens", "output_tokens", "cache_read_tokens",
            "cache_creation_tokens", "cache_creation_5m_tokens", "cache_creation_1h_tokens",
            "ttft_ms", "speed", "agent.name", "skill.name", "plugin.name", "mcp_server.name"),
        "api_error": common + ("status_code", "error", "attempt"),
        "api_retries_exhausted": common + (
            "status_code", "error", "total_attempts", "total_retry_duration_ms"),
    }
    max_body = 16 * 1024 * 1024

    # OTLP/JSON は int64 の intValue を文字列で送る
    def value(v):
        kind, x = next(iter(v.items()), (None, None))
        return int(x) if kind == "intValue" else x

    def attrs(o):
        return {x["key"]: value(x["value"]) for x in o.get("attributes", [])}

    class H(http.server.BaseHTTPRequestHandler):
        # 止まった接続をこの秒数で打ち切り、stderr に "Request timed out" を残す
        timeout = 10

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            if n > max_body:
                self.send_error(413)
                return
            lines = {}
            try:
                for rl in json.loads(self.rfile.read(n)).get("resourceLogs", []):
                    res = attrs(rl.get("resource", {}))
                    for sl in rl.get("scopeLogs", []):
                        for r in sl.get("logRecords", []):
                            a = {**res, **attrs(r)}
                            ks = keep.get(a.get("event.name"))
                            if ks:
                                lines.setdefault(a["event.name"], []).append(
                                    json.dumps({k: a[k] for k in ks if k in a}) + "\n")
            except (ValueError, KeyError, TypeError, AttributeError):
                lines = {}
            for name, ls in lines.items():
                with open(os.path.join(out, name + ".jsonl"), "a") as f:
                    f.writelines(ls)
                    f.flush()
                    # WSL の VM が落ちると書きかけのページが NUL で埋まる
                    os.fsync(f.fileno())
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b"{}")

        # 成功したリクエストだけ黙らせる。エラーとタイムアウトは stderr に出る
        def log_request(self, *a):
            pass

    http.server.HTTPServer(("127.0.0.1", ${toString port}), H).serve_forever()
  '';
  cmd = ["${pkgs.python3}/bin/python3" "${receiver}" stateDir];
in
  lib.mkMerge [
    {
      # settings.json の env は claude -p --setting-sources project で読まれないので、
      # シェルの環境変数で渡す
      home.sessionVariables = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_LOGS_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_LOGS_PROTOCOL = "http/json";
        OTEL_EXPORTER_OTLP_LOGS_ENDPOINT = "http://127.0.0.1:${toString port}/v1/logs";
      };
    }
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
        Unit.Description = "Receive Claude Code OTel API logs";
        Service = {
          ExecStart = lib.escapeShellArgs cmd;
          Restart = "always";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ]
