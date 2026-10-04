#!/usr/bin/env bash

feed_opml_entries() {
  # bulletty-only.opml is an import source, not part of the monitored feeds.
  local files=() file
  for file in "$OPML_DIR"/feeds*.opml; do
    [[ -f "$file" ]] || continue
    files+=("$file")
  done
  if [[ ${#files[@]} -eq 0 ]]; then
    printf '[]\n'
    return
  fi

  # shellcheck disable=SC2016 # $doc is a yq variable.
  feed_run yq eval-all -p=xml -o=json --xml-raw-token=false --xml-strict-mode \
    '. as $doc ireduce ([]; . + [$doc])' "${files[@]}" |
    feed_run deno run --no-prompt "${BASH_SOURCE[0]%/*}/feed-opml.ts"
}
