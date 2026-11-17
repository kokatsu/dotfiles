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
expect_failure() {
  if bash "$checker" "$@" >"$workdir/report" 2>&1; then
    echo "expected a document violation: $*" >&2
    exit 1
  fi
  grep -q 'no-prose-dash' "$workdir/report"
}
expect_failure --base missing-ref
printf '確認します──補足です。\n' >generated.md
expect_failure --worktree
mv generated.md "$workdir/generated.saved"
printf '設定を確認しました。\n' >note.md
git add note.md
printf '確認します──補足です。\n' >note.md
bash "$checker" --staged
expect_failure --worktree
git add note.md
printf '確認しました。\n' >note.md
expect_failure --staged
git commit -qm 'bad document fixture'
expect_failure --base "$base"
git add note.md
git mv 'old name.md' 'new name.md'
git rm -q removed.md
git commit -qm 'clean document fixture'
bash "$checker" --base "$base"
bash "$checker" --worktree
other_history=$(git commit-tree 'HEAD^{tree}' -m unrelated)
for unavailable in 0000000000000000000000000000000000000000 missing-ref "$other_history"; do
  bash "$checker" --base "$unavailable" >"$workdir/fallback" 2>&1
  grep -q 'checking only the HEAD commit' "$workdir/fallback"
done
printf '確認します──補足です。\n' >note.md
git add note.md
git commit -qm 'bad fallback document fixture'
expect_failure --base 0000000000000000000000000000000000000000
expect_failure --base missing-ref
printf 'documents: generated files, index snapshots, base range, rename and deletion passed\n'
