#!/usr/bin/env bash
# bin/status-dir の解決規則を確認する。Windows プロファイルの探索は /mnt/c 固定で
# 差し替えられないため、macOS 分岐と引数検査だけを見る
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
printf '#!/usr/bin/env bash\necho Darwin\n' >"$test_dir/bin/uname"
chmod +x "$test_dir/bin/uname"

[[ $(PATH="$test_dir/bin:$PATH" HOME="$test_dir/home" "$repo_root/bin/status-dir" feed-watch) == "$test_dir/home/.cache/feed-watch" ]]
if "$repo_root/bin/status-dir" 2>/dev/null; then
  echo "status-dir without a name must fail" >&2
  exit 1
fi
printf 'status-dir tests passed\n'
