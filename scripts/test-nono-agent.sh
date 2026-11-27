#!/usr/bin/env bash
set -eEuo pipefail
trap 'printf "line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# bwrap を使う経路だけを検証する
if [[ $(uname) != Linux ]]; then
  echo "nono-agent: skipped (Linux only)"
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
# /tmp からの起動は拒否されるため、/tmp だけを除いた写しを使う
sed 's#^/tmp/\* | ##' "$repo_root/scripts/nono-agent.sh" >"$test_dir/nono-agent.sh"
mkdir -p "$test_dir/bin" "$test_dir/home" "$test_dir/repo"
export TEST_DIR="$test_dir" HOME="$test_dir/home"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE HERDR_PANE_ID

cat >"$test_dir/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
while [[ $1 != -- ]]; do shift; done
shift
exec "$@"
EOF
cat >"$test_dir/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$TEST_DIR/calls"
EOF
cat >"$test_dir/bin/bwrap" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_DIR/args"
[[ $(<.git/commondir) == ./ ]] || exit 90
eval "${DURING:-}"
exit "${BWRAP_STATUS:-0}"
EOF
cat >"$test_dir/bin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "herdr $*" >>"$TEST_DIR/calls"
EOF
chmod +x "$test_dir"/bin/*
export PATH="$test_dir/bin:$PATH"
export NONO_AGENT_CLAUDE=/claude NONO_AGENT_CODEX=/codex NONO_AGENT_PI=/pi NONO_AGENT_WATCH=/watch
export NONO_AGENT_DOTFILES="$repo_root" NONO_AGENT_LIVE_PATHS="live/dir"

run() {
  local want=$1 got=0
  shift
  : >"$test_dir/calls"
  : >"$test_dir/args"
  bash -euo pipefail "$test_dir/nono-agent.sh" "$@" 2>"$test_dir/err" </dev/null || got=$?
  if ((got != want)); then
    printf 'nono-agent %s: exit %s, want %s\n' "$*" "$got" "$want" >&2
    cat "$test_dir/err" >&2
    exit 1
  fi
}
has_arg() { grep -Fxq -- "$1" "$test_dir/args"; }
lacks_arg() { ! has_arg "$1"; }
read_only() { grep -Fx -A2 -- --ro-bind "$test_dir/args" | grep -Fxq -- "$PWD/$1"; }

# 起動を拒否する場所と引数
cd "$test_dir/home"
run 1 claude
cd "$test_dir/repo"
run 1 claude
git init -q .
run 2 unknown

# 保護、終了コード、後始末
echo '{}' >.lefthook-local.jsonc
BWRAP_STATUS=7 run 7 claude
for path in .git/hooks .git/config .git/commondir .git/modules .claude .codex .pi .lefthook-local.jsonc; do
  read_only "$path"
done
lacks_arg "$PWD/live/dir"
[[ ! -e .git/commondir && ! -e .claude && ! -e .codex && ! -e .pi ]]

# 空でない .claude は消さない
mkdir .claude && echo '{}' >.claude/settings.json
run 0 claude
[[ -e .claude/settings.json ]]

# もともとあった空の .claude は残し、作ったものだけ消す
git init -q ../empty && cd ../empty
mkdir .claude
run 0 claude
[[ -d .claude && ! -e .codex && ! -e .pi ]]

# 最初のセッションを先に閉じても、最後のセッションが作成記録を引き継ぐ
wait_for_file() {
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ ! -f $1 ]] || return 0
    sleep 0.01
  done
  return 1
}
export -f wait_for_file
DURING='touch "$TEST_DIR/first-ready"; wait_for_file "$TEST_DIR/first-exit"' \
  bash -euo pipefail "$test_dir/nono-agent.sh" claude &
first=$!
wait_for_file "$test_dir/first-ready"
DURING='touch "$TEST_DIR/second-ready"; wait_for_file "$TEST_DIR/second-exit"' \
  bash -euo pipefail "$test_dir/nono-agent.sh" pi &
second=$!
wait_for_file "$test_dir/second-ready"
touch "$test_dir/first-exit"
wait "$first"
[[ -d .codex && -d .pi ]]
touch "$test_dir/second-exit"
wait "$second"
[[ -d .claude && ! -e .codex && ! -e .pi ]]

# git の参照先を別に持つリポジトリの commondir には触れない
echo ../shared >.git/commondir
run 1 claude
[[ $(<.git/commondir) == ../shared ]]
rm .git/commondir

# 異常終了で残った自分の commondir は引き継いで消す
echo ./ >.git/commondir
run 0 claude
[[ ! -e .git/commondir ]]

# core.hooksPath の先は未作成でも守る。macOS では守れないので拒否する
git config core.hooksPath .husky/_
run 0 claude
read_only .husky/_
printf '#!/bin/sh\necho Darwin\n' >"$test_dir/bin/uname"
chmod +x "$test_dir/bin/uname"
run 1 claude
rm "$test_dir/bin/uname"

# ルート自身がフックの置き場所なら守れない
for hooks_path in . ./ "$PWD"; do
  git config core.hooksPath "$hooks_path"
  run 1 claude
done
cd ../repo

# dotfiles では直接参照されている場所も守り、親もマウントポイントにする
mkdir -p live/dir
NONO_AGENT_DOTFILES=$PWD run 0 claude
read_only live/dir
has_arg "$PWD/live"

# 通常ファイルの .pi も壊さずに守る
echo x >.pi
run 0 claude
read_only .pi
[[ $(<.pi) == x ]]
rm .pi

# symlink は守れないので拒否する
mv .claude real && ln -s real .claude
run 1 claude
rm .claude && mv real .claude

# セッション中に現れたものを知らせる
DURING='touch lefthook.yml; mkdir -p sub/.git' run 0 claude
grep -Fxq lefthook.yml "$test_dir/err"
grep -Fxq sub/.git "$test_dir/err"
run 0 claude
[[ ! -s $test_dir/err ]]

# 保護が外れたら scope を強制終了する
DURING='echo /lost >&8' run 0 claude
grep -q '^systemctl --user kill --signal=KILL nono-agent-.*\.scope$' "$test_dir/calls"
grep -Fq /lost "$test_dir/err"

# Codex は対話のときだけ --no-daemon を付ける
run 0 codex
has_arg --no-daemon
run 0 codex review
lacks_arg --no-daemon

# Pi は専用の設定ディレクトリで起動する
run 0 pi
has_arg /pi
has_arg nono-agent-pi
has_arg "PI_CODING_AGENT_DIR=$(realpath -- "$HOME")/.local/share/nono-agent/pi"

# Herdr の socket や環境変数は渡さず、表示だけを外側で更新する
HERDR_PANE_ID=p1 HERDR_SOCKET_PATH=/sock run 0 claude
has_arg HERDR_SOCKET_PATH
grep -q 'report-metadata p1 --source nono --display-agent' "$test_dir/calls"
grep -q 'report-metadata p1 --source nono --clear-display-agent' "$test_dir/calls"

echo "nono-agent: ok"
