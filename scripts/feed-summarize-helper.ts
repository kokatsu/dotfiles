#!/usr/bin/env -S deno run --no-prompt
// feed-summarize-helper.ts — bin/feed-summarize が埋め込み Python で行っていた 2 処理
//
//   normalize-feed   stdin: `yq -p=xml -o=json` が出力したフィードの JSON
//                    stdout: entry 1 件 1 行の JSON (新しい順)
//   pending-entries  stdin: normalize-feed の JSONL / argv[1]: last_summarized_id
//                    stdout: その ID より前の行 (古い順)
//
// 入出力は stdin/stdout/argv だけなので Deno の権限フラグを一つも必要としない。
// 旧実装の pending 抽出は `last = '''$last_summarized_id'''` とシェル変数を Python
// ソースへ直接展開しており、外部フィード由来の ID に三重引用符や改行を仕込めば
// コードを書き換えられた。argv 経由ならソースに展開されないためこの経路は塞がる。

import { normalizeFeed, rec } from "./feed-entries.ts";

// last_summarized_id に一致する行の手前までを古い順で返す。ID が見つからなければ
// 全件、先頭が一致すれば 0 件になる。
function pendingEntries(input: string, last: string): string[] {
  const pending: string[] = [];
  for (const line of input.split("\n")) {
    if (line.trim().length === 0) continue;
    if (rec(JSON.parse(line))?.id === last) break;
    pending.push(line);
  }
  return pending.reverse();
}

async function main(): Promise<number> {
  const action = Deno.args[0] ?? "";
  const input = await new Response(Deno.stdin.readable).text();

  try {
    switch (action) {
      case "normalize-feed":
        // yq は整形式でない XML を非ゼロで落とし stdout に何も書かない。その失敗は
        // pipefail が伝えるのでここは黙って終わる。未閉鎖タグのように yq が解釈だけ
        // 諦めた入力は null になり、これも出力なしに落ち着く。
        if (input.trim().length === 0) return 0;
        for (const entry of normalizeFeed(input)) {
          console.log(JSON.stringify(entry));
        }
        return 0;
      case "pending-entries":
        for (const line of pendingEntries(input, Deno.args[1] ?? "")) {
          console.log(line);
        }
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
