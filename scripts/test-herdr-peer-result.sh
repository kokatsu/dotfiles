#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
wrapper="$repo_root/bin/herdr-peer"
export XDG_CONFIG_HOME="$repo_root/.config"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
git init -q "$workdir"
cd "$workdir"
printf '.kokatsu/\n' >.gitignore
mkdir -p .kokatsu/herdr-peer/task-one
result="$workdir/.kokatsu/herdr-peer/task-one/result.md"
cat >"$result" <<'RESULT'
# Result

task_id: task-one
kind: review
status: completed

## Outcome

No findings.

## Verification

Read the diff.

## Limitations

Runtime not checked.

HERDRPEERRESULTEND:task-one
RESULT
cp "$result" "$workdir/valid.md"
HERDR_ENV=0 bash "$wrapper" check-result "${result%/*}" review | jq -e '.format == "valid" and .completion == "unverified"' >/dev/null
sed '/Read the diff./a\
```yaml\
task_id: example\
kind: implement\
status: partial\
```\
' "$workdir/valid.md" >"$result"
bash "$wrapper" check-result "${result%/*}" review | jq -e '.format == "valid"' >/dev/null
for mode in task kind status footer section empty duplicate symlink missing; do
  cp "$workdir/valid.md" "$result"
  case $mode in
  task) sed 's/task_id: task-one/task_id: other/' "$result" >"$workdir/bad" ;;
  kind) sed 's/kind: review/kind: implement/' "$result" >"$workdir/bad" ;;
  status) sed 's/status: completed/status: unknown/' "$result" >"$workdir/bad" ;;
  footer) sed '$d' "$result" >"$workdir/bad" ;;
  section) sed 's/## Verification/## Other/' "$result" >"$workdir/bad" ;;
  empty) sed '/Read the diff./d' "$result" >"$workdir/bad" ;;
  duplicate) sed '/task_id:/p' "$result" >"$workdir/bad" ;;
  symlink)
    mv "$result" "$workdir/bad"
    ln -s "$workdir/bad" "$result"
    ;;
  missing) mv "$result" "$workdir/bad" ;;
  esac
  if [[ $mode != symlink && $mode != missing ]]; then mv "$workdir/bad" "$result"; fi
  if bash "$wrapper" check-result "${result%/*}" review >"$workdir/output" 2>&1; then
    echo "accepted invalid result: $mode" >&2
    exit 1
  fi
  [[ ! -L $result ]] || unlink "$result"
done
printf 'peer result: valid file and nine invalid cases passed\n'
