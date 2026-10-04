#!/usr/bin/env -S deno run --no-prompt
// feed-watch-helper.ts — bin/feed-watch のデータ変換
//
//   feed-ids             stdin: yq が出力したフィードの JSON
//                        stdout: エントリの ID (新しい順、1 行 1 件)
//   apply-check-results  stdin: NUL 区切りで status JSON、OPML の JSON 配列、
//                        続けて 1 フィードあたり name/type/url/category/ids
//                        stdout: 更新後の status JSON
//
// 入出力は stdin/stdout/argv だけなので Deno の権限フラグを一つも必要としない。
// ids は改行を含むので区切りは NUL になる。シェル変数は NUL を保持できないため、
// 呼び出し側は一時ファイルへ書き足してから渡す。

import { feedIds } from "./feed-entries.ts";
import { migrateFeedNames, type OpmlFeed } from "./feed-opml.ts";

interface Feed {
  last_seen_id?: string;
  unread_count?: number;
  type?: string;
  url?: string;
  category?: string;
  last_summarized_id?: string;
}

interface Status {
  feeds: Record<string, Feed>;
  [key: string]: unknown;
}

interface Update {
  name: string;
  type: string;
  url: string;
  category: string;
  ids: string;
}

const UPDATE_FIELDS = 5;

// jq の `// ""` と `-r` に対応する。null と false は空文字になる。
function str(value: unknown): string {
  return value === null || value === undefined || value === false
    ? ""
    : String(value);
}

function updateFeed(status: Status, update: Update): void {
  const existing = status.feeds[update.name];

  if (update.ids === "") {
    // ID が 1 つも取れなかったフィードは、既存エントリの category だけ追随させる
    if (existing) existing.category = update.category;
    return;
  }

  const ids = update.ids.split("\n");
  const latestId = ids[0];
  const prevId = str(existing?.last_seen_id);

  if (prevId === "") {
    // 初回: 未読 0 で最新 ID を記録
    status.feeds[update.name] = {
      last_seen_id: latestId,
      unread_count: 0,
      type: update.type,
      url: update.url,
      category: update.category,
    };
    return;
  }

  if (prevId === latestId) {
    // 変更なし (url, category は常に最新化)
    existing!.url = update.url;
    existing!.category = update.category;
    return;
  }

  // 前回の先頭 ID までを新規として数える。その ID が一覧から落ちていれば全件が
  // 新規になる
  let newCount = 0;
  for (const id of ids) {
    if (id === prevId) break;
    newCount += 1;
  }

  const feed: Feed = {
    last_seen_id: latestId,
    unread_count: (Number(existing?.unread_count) || 0) + newCount,
    type: update.type,
    url: update.url,
    category: update.category,
  };
  // 既存の last_summarized_id を保持 (上書きしない)
  const summarized = str(existing?.last_summarized_id);
  if (summarized !== "") feed.last_summarized_id = summarized;
  status.feeds[update.name] = feed;
}

// prune の基準は「OPML に書かれている名前」。取得に失敗したフィードも OPML には
// 残っているので、一時的なネットワーク障害でエントリを失わない
function applyCheckResults(input: string): string {
  const fields = input.split("\0");
  if (
    fields.length < 3 || fields[fields.length - 1] !== "" ||
    (fields.length - 3) % UPDATE_FIELDS !== 0
  ) {
    throw new Error(`malformed input: ${fields.length} NUL-separated fields`);
  }

  const status = JSON.parse(fields[0]) as Status;
  const entries = JSON.parse(fields[1]) as OpmlFeed[];
  const names = new Set(entries.map((entry) => entry.name));
  status.feeds = migrateFeedNames(status.feeds, entries);

  for (let i = 2; i + UPDATE_FIELDS <= fields.length - 1; i += UPDATE_FIELDS) {
    const [name, type, url, category, ids] = fields.slice(i, i + UPDATE_FIELDS);
    updateFeed(status, { name, type, url, category, ids });
  }

  // OPML から消えたフィードのエントリを落とす。残しておくと、未読を抱えたまま
  // 設定から外れたフィードがステータスバーに出続ける
  for (const name of Object.keys(status.feeds)) {
    if (!names.has(name)) delete status.feeds[name];
  }

  status.last_updated = Math.floor(Date.now() / 1000);
  return JSON.stringify(status, null, 2);
}

async function main(): Promise<number> {
  const action = Deno.args[0] ?? "";
  const input = await new Response(Deno.stdin.readable).text();

  try {
    switch (action) {
      case "feed-ids":
        for (const id of feedIds(input)) console.log(id);
        return 0;
      case "apply-check-results":
        console.log(applyCheckResults(input));
        return 0;
      default:
        console.error(`unknown action: ${action}`);
        return 2;
    }
  } catch (error) {
    // 壊れた入力でスタックトレースを吐かない。呼び出し元には非ゼロ終了で足りる。
    const reason = error instanceof Error ? error.message : String(error);
    console.error(`${action}: ${reason}`);
    return 1;
  }
}

Deno.exit(await main());
