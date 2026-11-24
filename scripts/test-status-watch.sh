#!/usr/bin/env bash
set -euo pipefail

# bin/status-watch が不完全な応答でキャッシュを書き換えず、他のサービスの更新を
# 続け、次の正常な応答で復旧することを file:// の応答で確かめる。

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

failures=0
# shellcheck source=scripts/test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/test-lib.sh"

cache="$test_dir/cache"
services=(status openai github)
mkdir -p "$test_dir/bin"
export STATUS_WATCH_STATUS_DIR="$cache"
export STATUS_WATCH_CLAUDE_URL="file://$test_dir/status.response"
export STATUS_WATCH_OPENAI_URL="file://$test_dir/openai.response"
export STATUS_WATCH_GITHUB_URL="file://$test_dir/github.response"

# 同じ秒に書かれると last_updated の不変を確かめられないので、呼び出し側が時刻を決める
cat >"$test_dir/bin/date" <<'MOCK'
#!/usr/bin/env bash
echo "$TEST_NOW"
MOCK
chmod +x "$test_dir/bin/date"
export PATH="$test_dir/bin:$PATH"

respond_all() {
  local service
  for service in "${services[@]}"; do
    printf '{"status":{"indicator":"%s","description":"d"}}\n' "$1" >"$test_dir/$service.response"
  done
}

check() {
  TEST_NOW=$1 "$repo_root/bin/status-watch" check 2>/dev/null
}

cached() {
  jq -c '[.indicator, .last_updated]' "$cache/$1.json"
}

expect_cached() {
  local actual
  actual=$(cached "$2") || actual=unreadable
  if [[ "$actual" == "$3" ]]; then
    pass "$1"
  else
    fail "$1: expected $3, got $actual"
  fi
}

expect_rejected() {
  local name=$1 body=$2 target=$3 service

  respond_all major
  check 100 || fail "$target: $name: setup failed"
  cp -p "$cache/$target.json" "$test_dir/before"

  respond_all minor
  printf '%s' "$body" >"$test_dir/$target.response"
  if check 200; then
    fail "$target: $name: check should fail"
  else
    pass "$target: $name: check fails"
  fi

  if cmp -s "$test_dir/before" "$cache/$target.json"; then
    pass "$target: $name: cache is unchanged"
  else
    fail "$target: $name: cache was rewritten"
  fi
  for service in "${services[@]}"; do
    [[ "$service" == "$target" ]] ||
      expect_cached "$target: $name: $service is updated" "$service" '["minor",200]'
  done

  respond_all none
  if check 300; then
    pass "$target: $name: next check succeeds"
  else
    fail "$target: $name: next check should succeed"
  fi
  expect_cached "$target: $name: cache recovers" "$target" '["none",300]'
}

valid='{"status":{"indicator":"none"}}'
for service in "${services[@]}"; do
  expect_rejected "empty body" '' "$service"
  expect_rejected "broken JSON" '{' "$service"
  expect_rejected "empty object" '{}' "$service"
  expect_rejected "array" '[]' "$service"
  expect_rejected "two objects" "$valid $valid" "$service"
  expect_rejected "empty indicator" '{"status":{"indicator":""}}' "$service"
  expect_rejected "non-string indicator" '{"status":{"indicator":1}}' "$service"
done

if [[ $failures -gt 0 ]]; then
  echo "status-watch tests: $failures failure(s)" >&2
  exit 1
fi
echo "status-watch tests passed"
