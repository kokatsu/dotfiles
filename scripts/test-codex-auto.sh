#!/usr/bin/env bash

set -euo pipefail

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/runtime"

cat >"$test_dir/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == app-server ]]; then
  printf '%s\n' "$@" >"$CODEX_AUTO_TEST_OUTPUT.server"
  socket_path=""
  for argument in "$@"; do
    if [[ $argument == unix://* ]]; then
      socket_path=${argument#unix://}
    fi
  done
  [[ -n "$socket_path" ]]
  exec deno eval '
    const listener = Deno.listen({ transport: "unix", path: Deno.args[0] });
    await new Promise((resolve) => Deno.addSignalListener("SIGTERM", resolve));
    listener.close();
  ' "$socket_path"
fi

printf '%s\n' "$@" >"$CODEX_AUTO_TEST_OUTPUT"
umask >"$CODEX_AUTO_TEST_OUTPUT.umask"
EOF
chmod +x "$test_dir/bin/codex"

run_launcher() {
  local output=$1
  shift
  (
    umask 022
    PATH="$test_dir/bin:$PATH" \
      XDG_RUNTIME_DIR="$test_dir/runtime" \
      CODEX_AUTO_TEST_OUTPUT="$output" \
      bash scripts/codex-auto.sh "$@"
  )
}

default_output="$test_dir/default.args"
run_launcher "$default_output" --help
mapfile -t default_args <"$default_output"

default_cd_count=0
for ((index = 0; index < ${#default_args[@]}; index++)); do
  if [[ ${default_args[index]} == -C ]]; then
    ((default_cd_count += 1))
    [[ ${default_args[index + 1]} == "$PWD" ]]
  fi
done
[[ $default_cd_count -eq 1 ]]
grep -Fx -- 'notify=["codex-auto-title"]' "$default_output.server" >/dev/null
if grep -Fx -- 'notify=["codex-auto-title"]' "$default_output" >/dev/null; then
  echo "codex-auto test: notify override leaked into the TUI client" >&2
  exit 1
fi
[[ $(<"$default_output.umask") == 0022 ]]

explicit_output="$test_dir/explicit.args"
run_launcher "$explicit_output" -C /tmp --help
mapfile -t explicit_args <"$explicit_output"

explicit_cd_count=0
for ((index = 0; index < ${#explicit_args[@]}; index++)); do
  if [[ ${explicit_args[index]} == -C ]]; then
    ((explicit_cd_count += 1))
    [[ ${explicit_args[index + 1]} == /tmp ]]
  fi
done
[[ $explicit_cd_count -eq 1 ]]

if find "$test_dir/runtime" -mindepth 1 -print -quit | grep -q .; then
  echo "codex-auto test: runtime directory was not cleaned up" >&2
  exit 1
fi

echo "codex-auto launcher tests passed"
