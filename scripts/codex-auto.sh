# shellcheck shell=bash
set -euo pipefail

runtime_parent=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
runtime_dir=$(mktemp -d "$runtime_parent/codex-auto.XXXXXX")
socket_path="$runtime_dir/app-server.sock"
if ((${#socket_path} >= 100)); then
  rmdir "$runtime_dir"
  runtime_dir=$(mktemp -d /tmp/codex-auto.XXXXXX)
  socket_path="$runtime_dir/app-server.sock"
fi
app_server_log="$runtime_dir/app-server.log"
app_server_pid=""

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM

  if [[ -n "$app_server_pid" ]] && kill -0 "$app_server_pid" 2>/dev/null; then
    kill "$app_server_pid" 2>/dev/null || true
    for _ in {1..20}; do
      if ! kill -0 "$app_server_pid" 2>/dev/null; then
        break
      fi
      sleep 0.05
    done
    if kill -0 "$app_server_pid" 2>/dev/null; then
      kill -KILL "$app_server_pid" 2>/dev/null || true
    fi
    wait "$app_server_pid" 2>/dev/null || true
  fi

  if [[ $status -ne 0 && -s "$app_server_log" ]]; then
    echo "codex-auto: app-server log:" >&2
    tail -n 20 "$app_server_log" >&2
  fi

  rm -f "$socket_path" "$app_server_log"
  rmdir "$runtime_dir" 2>/dev/null || true
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

export CODEX_AUTO_TITLE_SOCKET="$socket_path"

codex app-server \
  -c 'notify=["codex-auto-title"]' \
  --listen "unix://$socket_path" \
  >"$app_server_log" 2>&1 &
app_server_pid=$!

for _ in {1..100}; do
  if [[ -S "$socket_path" ]]; then
    break
  fi
  if ! kill -0 "$app_server_pid" 2>/dev/null; then
    echo "codex-auto: app-server exited before creating its socket" >&2
    exit 1
  fi
  sleep 0.05
done

if [[ ! -S "$socket_path" ]]; then
  echo "codex-auto: timed out waiting for the app-server socket" >&2
  exit 1
fi

codex_args=(--remote "unix://$socket_path")
has_cd=false
for argument in "$@"; do
  case "$argument" in
  -C | --cd | --cd=*)
    has_cd=true
    ;;
  esac
done
if [[ $has_cd == false ]]; then
  codex_args+=(-C "$PWD")
fi

codex "${codex_args[@]}" "$@"
