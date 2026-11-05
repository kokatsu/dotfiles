#!/usr/bin/env bash
set -eEuo pipefail
trap 'printf "line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

repo_root=$(git rev-parse --show-toplevel)
dc_agent="$repo_root/bin/dc-agent"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
export TEST_DIR="$test_dir"

# 呼び出しを 1 行 1 コマンドで calls に記録する。devcontainer は受け取った HERDR_AGENT を
# 先頭に付け、DEVCONTAINER_STATUS で終了する
cat >"$test_dir/bin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "herdr $*" >>"$TEST_DIR/calls"
exit "${HERDR_STATUS:-0}"
EOF
cat >"$test_dir/bin/devcontainer" <<'EOF'
#!/usr/bin/env bash
echo "HERDR_AGENT=$HERDR_AGENT devcontainer $*" >>"$TEST_DIR/calls"
exit "${DEVCONTAINER_STATUS:-0}"
EOF
chmod +x "$test_dir/bin/herdr" "$test_dir/bin/devcontainer"
export PATH="$test_dir/bin:$PATH"

# run <期待する終了コード> [dc-agent の引数...]。期待する calls は stdin から受け取る
run() {
  local want=$1 got=0 expected
  shift
  expected=$(cat)
  : >"$test_dir/calls"
  "$dc_agent" "$@" || got=$?
  if ((got != want)); then
    printf 'dc-agent %s: exit %s, want %s\n' "$*" "$got" "$want" >&2
    exit 1
  fi
  if [[ $(<"$test_dir/calls") != "$expected" ]]; then
    printf 'dc-agent %s: unexpected calls\n--- expected\n%s\n--- actual\n%s\n' \
      "$*" "$expected" "$(<"$test_dir/calls")" >&2
    exit 1
  fi
}

export HERDR_PANE_ID=p1

DEVCONTAINER_STATUS=7 run 7 claude --dangerously-skip-permissions <<'EOF'
herdr pane report-metadata p1 --source devcontainer --display-agent   claude
HERDR_AGENT=claude devcontainer exec --workspace-folder . claude --dangerously-skip-permissions
herdr pane report-metadata p1 --source devcontainer --clear-display-agent
EOF

HERDR_STATUS=1 run 0 codex <<'EOF'
herdr pane report-metadata p1 --source devcontainer --display-agent   codex
HERDR_AGENT=codex devcontainer exec --workspace-folder . codex
herdr pane report-metadata p1 --source devcontainer --clear-display-agent
EOF

unset HERDR_PANE_ID
run 0 claude <<'EOF'
HERDR_AGENT=claude devcontainer exec --workspace-folder . claude
EOF

run 2 </dev/null

echo "dc-agent: ok"
