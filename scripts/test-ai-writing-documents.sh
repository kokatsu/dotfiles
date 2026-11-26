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
status=0
bash "$checker" --staged >"$workdir/report" 2>&1 || status=$?
[[ $status == 1 ]]
grep -Eq '^legacy\.md:.*no-prose-dash' "$workdir/report"
git commit -qm fixture
base=$(git rev-parse HEAD)

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
real_textlint_path=$PATH
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
pr_head=$(git rev-parse HEAD)
git switch -qc fixture-base "$base"
printf 'base branch document\n' >base-only.md
git add base-only.md
git commit -qm 'base advances'
advanced_base=$(git rev-parse HEAD)
git switch -q --detach "$pr_head"
check_snapshot 1 --base "$other_history" </dev/null
grep -q 'Comparison base is not an ancestor of HEAD' "$workdir/report"
check_snapshot 1 --base "$advanced_base" </dev/null
grep -q 'Comparison base is not an ancestor of HEAD' "$workdir/report"
check_snapshot 0 --push-base "$other_history" </dev/null
check_snapshot 23 --push-base "$advanced_base" <<'FILES'
new name.md=確認しました。
note.md=edited
FILES
for unavailable in 0000000000000000000000000000000000000000 ffffffffffffffffffffffffffffffffffffffff; do
  check_snapshot 23 --push-base "$unavailable" <<'FILES'
legacy.md=以前の文書──変更対象外です。
new name.md=確認しました。
note.md=edited
FILES
  grep -q 'Previous push SHA unavailable; checking all documents in HEAD' "$workdir/report"
done
check_snapshot 1 --push-base invalid-ref </dev/null
grep -q 'Invalid previous push SHA' "$workdir/report"
git switch -q fixture-base
git merge -q --no-edit "$pr_head"
check_snapshot 0 --base 'HEAD^1' <<'FILES'
new name.md=確認しました。
note.md=edited
FILES

for unavailable in '' 0000000000000000000000000000000000000000 missing-ref; do
  check_snapshot 1 --base "$unavailable" </dev/null
  grep -q 'Cannot resolve comparison base' "$workdir/report"
done

mkdir scripts
ln -s "$checker" scripts/check-ai-writing.sh
cp "$repo_root/justfile" ./justfile
git switch -q --detach "$pr_head"
: >"$SNAPSHOT"
GITHUB_ACTIONS=true GITHUB_EVENT_NAME=push AI_WRITING_BASE="$advanced_base" LINT_STATUS=0 just ai-writing-check
diff -u - <(LC_ALL=C sort "$SNAPSHOT") <<'FILES'
new name.md=確認しました。
note.md=edited
FILES
status=0
GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request AI_WRITING_BASE="$advanced_base" just ai-writing-check >"$workdir/report" 2>&1 || status=$?
[[ $status == 1 ]]
grep -q 'Comparison base is not an ancestor of HEAD' "$workdir/report"
status=0
GITHUB_ACTIONS=true AI_WRITING_BASE='' just ai-writing-check >"$workdir/report" 2>&1 || status=$?
[[ $status == 1 ]]
grep -Fxq 'AI_WRITING_BASE is required in GitHub Actions.' "$workdir/report"
printf 'local\n' >local.md
: >"$SNAPSHOT"
GITHUB_ACTIONS=false AI_WRITING_BASE='' LINT_STATUS=0 just ai-writing-check
grep -Fxq 'local.md=local' "$SNAPSHOT"
check_snapshot 0 --staged </dev/null
mv local.md "$workdir/local.saved"
printf '対象外の文章──リンク先です。\n' >target.txt
ln -s target.txt doc.md
git add -- doc.md target.txt
git commit -qm 'symlink document'
link_base=$(git rev-parse HEAD)
diverged_link_base=$(git commit-tree 'HEAD^{tree}' -p "$pr_head" -m 'diverged symlink document')
mv doc.md "$workdir/doc-link"
printf '更新した文章──検査対象です。\n' >doc.md
check_snapshot 23 --worktree <<<'doc.md=更新した文章──検査対象です。'
git add -- doc.md
check_snapshot 23 --staged <<<'doc.md=更新した文章──検査対象です。'
git commit -qm 'replace symlink with a regular document'
regular_base=$(git rev-parse HEAD)
check_snapshot 23 --base "$link_base" <<<'doc.md=更新した文章──検査対象です。'
check_snapshot 23 --push-base "$diverged_link_base" <<<'doc.md=更新した文章──検査対象です。'
status=0
PATH=$real_textlint_path bash "$checker" --push-base "$diverged_link_base" >"$workdir/report" 2>&1 || status=$?
[[ $status == 1 ]]
grep -Eq '^doc\.md:.*no-prose-dash' "$workdir/report"

mv doc.md "$workdir/doc-regular"
ln -s target.txt doc.md
check_snapshot 0 --worktree </dev/null
git add -- doc.md
check_snapshot 0 --staged </dev/null
git commit -qm 'restore document symlink'
check_snapshot 0 --base "$regular_base" </dev/null
check_snapshot 0 --push-base "$regular_base" </dev/null
printf 'documents: worktree, index, PR merge, push range, missing base and file type checks passed\n'
