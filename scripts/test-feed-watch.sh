#!/usr/bin/env bash
set -eEuo pipefail

# bin/feed-watch の変換部分 (OPML パース、エントリ ID 抽出、未読カウント) を
# check/read サブコマンド越しに確かめる。内部関数を呼ばないので、変換の実装が
# 別言語へ移っても同じ判定がそのまま使える。
#
# ロック、取得失敗時の保持、prune、不正 JSON の扱いは
# scripts/test-feed-status.sh が持つ。ここでは重複させない。

report_failure() {
  local rc=$? line=$1
  printf '%s:%s: exit %s: %s\n' "${BASH_SOURCE[0]##*/}" "$line" "$rc" "$BASH_COMMAND" >&2
}
trap 'report_failure "$LINENO"' ERR

# feed_lock が util-linux の flock を使う。
if [[ $(uname -s) != Linux ]]; then
  echo 'Skipping Linux feed watch tests'
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

export FEED_TEST_DIR="$test_dir"
export FEED_WATCH_OPML_DIR="$test_dir/opml"
export FEED_WATCH_STATUS_DIR="$test_dir/state"
status_file="$FEED_WATCH_STATUS_DIR/status.json"
mkdir -p "$FEED_WATCH_OPML_DIR" "$FEED_WATCH_STATUS_DIR" "$test_dir/bin" \
  "$test_dir/http" "$test_dir/gh"
export PATH="$test_dir/bin:$PATH"

cat >"$test_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url=${!#}
key=$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')
[[ -f "$FEED_TEST_DIR/http/$key" ]] || exit 22
cat "$FEED_TEST_DIR/http/$key"
MOCK

cat >"$test_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
key=$(printf '%s' "$2" | tr -c 'A-Za-z0-9' '_')
[[ -f "$FEED_TEST_DIR/gh/$key" ]] || exit 1
cat "$FEED_TEST_DIR/gh/$key"
MOCK
chmod +x "$test_dir/bin/curl" "$test_dir/bin/gh"

fixture_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }
put_http() { cat >"$test_dir/http/$(fixture_key "$1")"; }
put_gh() { cat >"$test_dir/gh/$(fixture_key "$1")"; }
write_opml() { cat >"$FEED_WATCH_OPML_DIR/$1"; }
check() { bash "$repo_root/bin/feed-watch" check; }
assert() { jq -e "$1" "$status_file" >/dev/null; }

alpha=https://example.com/alpha.atom
nohtml=https://example.com/nohtml.atom
gamma=https://example.com/gamma.rss
extra=https://example.com/extra.atom
only=https://example.com/only.atom

# --- OPML のパース ---
write_opml feeds.opml <<XML
<opml><body>
<outline text="Cat A" title="Blog">
<outline text="Alpha &amp; Beta" title="ignored" xmlUrl="$alpha" htmlUrl="https://example.com/alpha" type="rss" />
<outline text="NoHtml" xmlUrl="$nohtml" type="rss" />
</outline>
<outline text="Cat B">
<outline text="Gamma" xmlUrl="$gamma" htmlUrl="https://example.com/gamma" />
</outline>
</body></opml>
XML
write_opml feeds-extra.opml <<XML
<opml><body>
<outline text="Cat C">
<outline text="Extra" xmlUrl="$extra" htmlUrl="https://example.com/extra" />
</outline>
</body></opml>
XML
# feeds*.opml 以外は未読カウントの対象外。
write_opml bulletty-only.opml <<XML
<opml><body>
<outline text="Cat D">
<outline text="Only" xmlUrl="$only" htmlUrl="https://example.com/only" />
</outline>
</body></opml>
XML

# Atom は先頭の <id> がフィード自身なので飛ばす。
put_http "$alpha" <<'XML'
<feed><id>tag:example.com,2026:alpha</id>
<entry><id>a3</id></entry>
<entry><id>a2</id></entry>
<entry><id>a1</id></entry>
</feed>
XML
put_http "$nohtml" <<'XML'
<feed><id>tag:self</id><entry><id>n1</id></entry></feed>
XML
# <id> を持たないフィードは RSS とみなして <guid> を読む。
put_http "$gamma" <<'XML'
<rss><channel>
<item><guid isPermaLink="false">g2</guid></item>
<item><guid>g1</guid></item>
</channel></rss>
XML
put_http "$extra" <<'XML'
<feed><id>tag:self</id><entry><id>e1</id></entry></feed>
XML
put_http "$only" <<'XML'
<feed><id>tag:self</id><entry><id>o1</id></entry></feed>
XML

check
# 名前は OPML の生のまま。実体参照を解いた名前を使うと configured_names が
# status.json の鍵と一致せず、次の check で全エントリが prune される。
assert '.feeds["Alpha &amp; Beta"] == {"last_seen_id":"a3","unread_count":0,"type":"feed","url":"https://example.com/alpha","category":"Cat A"}'
# htmlUrl の無い outline は xmlUrl を URL に使う。
assert '.feeds.NoHtml.url == "'"$nohtml"'"'
assert '.feeds.Gamma == {"last_seen_id":"g2","unread_count":0,"type":"feed","url":"https://example.com/gamma","category":"Cat B"}'
assert '.feeds.Extra.category == "Cat C"'
assert '.feeds.Only == null'
assert '.last_updated | type == "number"'

# --- 初回は未読 0。以後は前回の先頭 ID まで数える ---
put_http "$alpha" <<'XML'
<feed><id>tag:self</id>
<entry><id>a5</id></entry>
<entry><id>a4</id></entry>
<entry><id>a3</id></entry>
<entry><id>a2</id></entry>
</feed>
XML
check
assert '.feeds["Alpha &amp; Beta"] | .last_seen_id == "a5" and .unread_count == 2'

# 先頭 ID が変わらなければ数え直さない。url と category は毎回最新化する。
write_opml feeds.opml <<XML
<opml><body>
<outline text="Cat A2" title="Blog">
<outline text="Alpha &amp; Beta" xmlUrl="$alpha" htmlUrl="https://example.com/alpha2" type="rss" />
<outline text="NoHtml" xmlUrl="$nohtml" type="rss" />
</outline>
<outline text="Cat B">
<outline text="Gamma" xmlUrl="$gamma" htmlUrl="https://example.com/gamma" />
</outline>
</body></opml>
XML
check
assert '.feeds["Alpha &amp; Beta"] | .unread_count == 2 and .category == "Cat A2" and .url == "https://example.com/alpha2"'

# 前回の ID が一覧に無ければ全件を新着として数える。
put_http "$alpha" <<'XML'
<feed><id>tag:self</id>
<entry><id>b3</id></entry>
<entry><id>b2</id></entry>
<entry><id>b1</id></entry>
</feed>
XML
check
assert '.feeds["Alpha &amp; Beta"] | .last_seen_id == "b3" and .unread_count == 5'

# --- last_summarized_id ---
# 更新のあったフィードでは引き継ぐ。
jq '.feeds["Alpha &amp; Beta"].last_summarized_id = "b3"' "$status_file" >"$test_dir/tmp"
mv "$test_dir/tmp" "$status_file"
put_http "$alpha" <<'XML'
<feed><id>tag:self</id><entry><id>b4</id></entry><entry><id>b3</id></entry></feed>
XML
check
assert '.feeds["Alpha &amp; Beta"] | .unread_count == 6 and .last_summarized_id == "b3"'

# last_seen_id を持たないエントリは初回扱いになり、last_summarized_id は残らない。
jq '.feeds.Gamma = {"last_summarized_id":"g1","unread_count":9,"category":"stale"}' "$status_file" >"$test_dir/tmp"
mv "$test_dir/tmp" "$status_file"
check
assert '.feeds.Gamma == {"last_seen_id":"g2","unread_count":0,"type":"feed","url":"https://example.com/gamma","category":"Cat B"}'

# --- エントリ ID が 1 つも取れなかったフィード ---
# 既存エントリは category だけ更新し、未読は動かさない。
put_http "$gamma" <<'XML'
<rss><channel><item><title>no identifier</title></item></channel></rss>
XML
write_opml feeds.opml <<XML
<opml><body>
<outline text="Cat A2">
<outline text="Alpha &amp; Beta" xmlUrl="$alpha" htmlUrl="https://example.com/alpha2" type="rss" />
<outline text="NoHtml" xmlUrl="$nohtml" type="rss" />
</outline>
<outline text="Cat B2">
<outline text="Gamma" xmlUrl="$gamma" htmlUrl="https://example.com/gamma-moved" />
<outline text="EmptyNew" xmlUrl="$gamma" htmlUrl="https://example.com/empty" />
</outline>
</body></opml>
XML
check
assert '.feeds.Gamma | .category == "Cat B2" and .last_seen_id == "g2" and .url == "https://example.com/gamma"'
# 未知のフィードはエントリを作らない。
assert '.feeds.EmptyNew == null'

# --- GitHub フィードは gh api から SHA を取る ---
put_gh 'repos/example/demo/commits?per_page=100' <<'IDS'
sha2
sha1
IDS
write_opml feeds.opml <<XML
<opml><body>
<outline text="Cat A2">
<outline text="Alpha &amp; Beta" xmlUrl="$alpha" htmlUrl="https://example.com/alpha2" type="rss" />
<outline text="Demo" xmlUrl="https://github.com/example/demo/commits.atom" htmlUrl="https://github.com/example/demo" />
</outline>
</body></opml>
XML
check
assert '.feeds.Demo | .type == "github" and .last_seen_id == "sha2" and .unread_count == 0'

# --- read ---
bash "$repo_root/bin/feed-watch" read '&amp; Beta'
assert '.feeds["Alpha &amp; Beta"].unread_count == 0'
jq '.feeds.Demo.unread_count = 3' "$status_file" >"$test_dir/tmp"
mv "$test_dir/tmp" "$status_file"
if bash "$repo_root/bin/feed-watch" read Missing 2>"$test_dir/no-match"; then exit 1; fi
grep -Fq "No feed matching 'Missing'" "$test_dir/no-match"
bash "$repo_root/bin/feed-watch" read --all
assert '[.feeds[].unread_count] | all(. == 0)'

printf 'Feed watch transform tests passed\n'
