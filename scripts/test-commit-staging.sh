#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export LEFTHOOK_CONFIG="$repo_root/.lefthook.jsonc"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git init -q "$workdir"
cd "$workdir"
git config user.name Fixture
git config user.email fixture@example.invalid
git config commit.gpgsign false
for file in partial.json untouched.json; do printf '{ "a": 0, "b": 0 }\n' >"$file"; done
git add .
git commit -qm fixture
cat >.git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
exec lefthook run pre-commit --job biome --no-auto-install
HOOK
chmod +x .git/hooks/pre-commit
printf '{ "a": 1, "b": 0 }\n' >partial.json
git add partial.json
printf '{ "a": 1, "b": 2 }\n' >partial.json
printf '{ "a": 3, "b": 0 }\n' >untouched.json
git show :partial.json >expected-staged
cp partial.json expected-working
cp untouched.json expected-untouched
git commit -qm 'fixture change' >hook-output 2>&1 || {
  cat hook-output
  exit 1
}
git show HEAD:partial.json >actual-staged
cmp expected-staged actual-staged
cmp expected-working partial.json
cmp expected-untouched untouched.json
[[ $(git diff HEAD^ HEAD --name-only) == partial.json ]]
git show HEAD:untouched.json | grep -qxF '{ "a": 0, "b": 0 }'
printf 'commit staging: partial hunks and wholly unstaged files preserved by Lefthook\n'
