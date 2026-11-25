#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
checker="$repo_root/scripts/check-ai-writing.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
mkdir -p "$workdir/repo/.config"
cp -R "$repo_root/.config/ai-writing" "$workdir/repo/.config/ai-writing"
cd "$workdir/repo"
git init -q
git config user.name Fixture
git config user.email fixture@example.invalid
git config commit.gpgsign false
git config core.hooksPath /dev/null
for file in note.md removed.md 'old name.md'; do printf '確認しました。\n' >"$file"; done
printf '以前の文書──変更対象外です。\n' >legacy.md
git add .
git commit -qm fixture
base=$(git rev-parse HEAD)
status=0
bash "$checker" --base missing-ref >"$workdir/report" 2>&1 || status=$?
[[ $status == 1 ]]
grep -Eq '^legacy\.md:.*no-prose-dash' "$workdir/report"

mkdir "$workdir/bin"
cat >"$workdir/bin/textlint" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
while [[ $1 != -- ]]; do shift; done
shift
(( $# > 0 )) || exit 99
for file do
  printf '%s=' "${file#*/files/}"
  cat "$file"
done >>"$SNAPSHOT"
exit "$LINT_STATUS"
STUB
chmod +x "$workdir/bin/textlint"
export PATH="$workdir/bin:$PATH" SNAPSHOT="$workdir/snapshot"

# Each fixture document has one line. Compare both its selected path and its contents.
check_snapshot() {
  local expected_status=$1 actual_status=0
  shift
  : >"$SNAPSHOT"
  LINT_STATUS=$expected_status bash "$checker" "$@" >"$workdir/report" 2>&1 || actual_status=$?
  [[ $actual_status == "$expected_status" ]]
  diff -u - <(LC_ALL=C sort "$SNAPSHOT")
}

printf 'generated\n' >generated.md
check_snapshot 23 --worktree <<<'generated.md=generated'
mv generated.md "$workdir/generated.saved"
printf 'staged\n' >note.md
git add note.md
printf 'edited\n' >note.md
check_snapshot 0 --staged <<<'note.md=staged'
check_snapshot 23 --staged <<<'note.md=staged'
check_snapshot 0 --worktree <<<'note.md=edited'
git commit -qm 'staged document fixture'
check_snapshot 23 --base "$base" <<<'note.md=staged'
git add note.md
git mv 'old name.md' 'new name.md'
git rm -q removed.md
git commit -qm 'rename and deletion fixture'
check_snapshot 0 --base "$base" <<'FILES'
new name.md=確認しました。
note.md=edited
FILES
check_snapshot 0 --worktree </dev/null
other_history=$(git commit-tree 'HEAD^{tree}' -m unrelated)
for unavailable in 0000000000000000000000000000000000000000 missing-ref "$other_history"; do
  check_snapshot 0 --base "$unavailable" <<'FILES'
new name.md=確認しました。
note.md=edited
FILES
  grep -q 'checking only the HEAD commit' "$workdir/report"
done
printf 'fallback\n' >note.md
git add note.md
git commit -qm 'fallback document fixture'
for unavailable in 0000000000000000000000000000000000000000 missing-ref; do
  check_snapshot 23 --base "$unavailable" <<<'note.md=fallback'
done
check_snapshot 0 --staged </dev/null
printf 'documents: generated files, index snapshots, base range, rename and deletion passed\n'
