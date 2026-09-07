#!/usr/bin/env bash
# feed-watch / feed-summarize 共通の状態更新。呼び出し元で STATUS_FILE を設定する。

# 外部コマンドやそのデーモンへロック用 FD を渡さない。
feed_run() {
  "$@" 8>&- 9>&-
}

feed_lock() {
  local fd="$1" path="$2"
  if flock -w "${FEED_WATCH_LOCK_TIMEOUT:-300}" -x "$fd"; then
    return 0
  fi
  echo "Failed to acquire feed lock within timeout: $path" >&2
  return 1
}

feed_status_validate() {
  local label="$1"
  if jq -e 'type == "object" and (.feeds | type == "object")' >/dev/null; then
    return 0
  fi
  echo "Invalid feed status ($label): $STATUS_FILE; existing file preserved" >&2
  return 1
}

# Windows の読み取りハンドルによる一時的な共有違反を待つ。
# 最後まで失敗した場合も、旧ファイルを消したり直接上書きしたりしない。
feed_status_publish() {
  local temp_file="$1" delay error
  for delay in 0.1 0.2 0.4 0.8 last; do
    if error=$(mv -f "$temp_file" "$STATUS_FILE" 2>&1); then
      return 0
    fi
    if [[ "$delay" != last ]]; then
      sleep "$delay"
    fi
  done
  echo "Failed to publish feed status after 5 attempts: $STATUS_FILE; existing file preserved" >&2
  printf '%s\n' "$error" >&2
  return 1
}

feed_status_read() {
  if [[ -f "$STATUS_FILE" ]]; then
    cat "$STATUS_FILE"
  else
    printf '%s\n' '{"feeds":{}}'
  fi
}

# 通信や対話はロックの外で済ませ、最新状態に対する変更だけを callback に渡す。
# ロックファイルは削除しない (待機中のプロセスと別 inode をロックするのを防ぐ)。
feed_status_update() (
  local callback="$1" current temp_file
  shift
  mkdir -p "$(dirname "$STATUS_FILE")" || exit $?
  exec 9>"$STATUS_FILE.lock" || exit $?
  feed_lock 9 "$STATUS_FILE.lock" || exit $?
  current=$(feed_status_read) || exit $?
  printf '%s\n' "$current" | feed_status_validate input || exit $?
  temp_file=$(mktemp "$STATUS_FILE.XXXXXX") || exit $?
  trap 'rm -f "$temp_file"' EXIT
  "$callback" "$current" "$@" >"$temp_file" || exit $?
  feed_status_validate output <"$temp_file" || exit $?
  feed_status_publish "$temp_file"
)

feed_status_mark_read() {
  local current="$1" names="$2"
  printf '%s\n' "$current" | jq --argjson names "$names" '
    .feeds |= with_entries(
      if $names == null or (.key as $k | $names | index($k)) != null
      then .value.unread_count = 0 else . end)
  '
}

feed_status_mark_summarized() {
  local current="$1" name="$2" id="$3"
  # 要約中に OPML から削除されたフィードは復活させない。
  printf '%s\n' "$current" | jq --arg name "$name" --arg id "$id" '
    if .feeds[$name] != null then .feeds[$name].last_summarized_id = $id else . end
  '
}
