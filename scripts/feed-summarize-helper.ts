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

// yq の XML → JSON 変換の約束事。属性は "+@name"、属性付き要素の本文は "+content"、
// XML 宣言は "+p_xml" になり、同名の兄弟要素は配列にまとまる。空要素は null。
const ATTR_PREFIX = "+";
const CONTENT_KEY = "+content";
const HREF_KEY = "+@href";

const ENTRY_NAMES = new Set(["entry", "item"]);
const DATE_NAMES = new Set(["published", "updated", "pubDate"]);

interface Entry {
  id: string;
  title: string;
  link: string;
  date: string;
}

function rec(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

// ElementTree は名前空間 URI を除いた局所名で判定していた。yq は前置き名前空間を
// キーに残す (`atom:entry`, `dc:date`) ので、コロンより前を落として揃える。
function localName(key: string): string {
  const colon = key.indexOf(":");
  return colon < 0 ? key : key.slice(colon + 1);
}

// "+@attr" / "+content" / "+p_xml" は yq の記法であって子要素ではない。
function isElement(key: string): boolean {
  return !key.startsWith(ATTR_PREFIX);
}

// 子要素のテキスト。`(child.text or "").strip()` に対応する。
function textOf(value: unknown): string {
  if (typeof value === "string") return value.trim();
  const obj = rec(value);
  if (obj === null) return "";
  const content = obj[CONTENT_KEY];
  return typeof content === "string" ? content.trim() : "";
}

// href 属性。旧実装は属性値をそのまま使っていたので trim しない。
function hrefOf(value: unknown): string {
  const obj = rec(value);
  if (obj === null) return "";
  const href = obj[HREF_KEY];
  return typeof href === "string" ? href : "";
}

// entry 直下の子だけをキー順に見て、フィールドごとに最初の非空値を採る。
// yq は同名の兄弟を配列へ畳むが、ElementTree は 1 件ずつ見ていたので配列も
// 展開して同じ「最初の非空」判定に通す。`<link/><link href="x"/>` で先頭の
// 空要素ではなく x を拾うのはこのため。
//
// ただし配列の中身はキーの位置にまとめて並ぶので、同名要素が複数あって最初が
// 空のときだけ、競合する別名より後ろの値を拾うことがある
// (`<guid/><id>x</id><guid>y</guid>` は ElementTree なら x、ここでは y)。
// 理由は collectEntries と同じ。
function buildEntry(value: unknown): Entry {
  const entry: Entry = { id: "", title: "", link: "", date: "" };
  const obj = rec(value);
  for (const [key, raw] of Object.entries(obj ?? {})) {
    if (!isElement(key)) continue;
    const name = localName(key);
    for (const child of Array.isArray(raw) ? raw : [raw]) {
      if ((name === "id" || name === "guid") && !entry.id) {
        entry.id = textOf(child);
      } else if (name === "title" && !entry.title) {
        entry.title = textOf(child);
      } else if (name === "link" && !entry.link) {
        entry.link = hrefOf(child) || textOf(child);
      } else if (DATE_NAMES.has(name) && !entry.date) {
        entry.date = textOf(child);
      }
    }
  }
  if (!entry.id) entry.id = entry.link;
  return entry;
}

// yq が出力した JSON をキー順に走査して entry/item を集める。`.feed.entry` や
// `.rss.channel.item` のような固定パスには当てず、深さも問わない。
//
// 意図的な差分: yq は同名要素をキーごとの配列へ畳むため、名前の違う要素同士の
// 前後関係は JSON から復元できない。`<entry>a</entry><item>b</item><entry>c</entry>`
// は ElementTree なら a,b,c だが、ここでは名前ごとに固まって a,c,b になる。
// yq に順序を残す出力オプションはなく、直すには XML パーサーを自前で持つか依存を
// 増やすしかない。entry と item を同じ階層に混ぜるフィードは現在の対象にないので、
// この差分は受け入れる。
function collectEntries(value: unknown, out: unknown[]): void {
  const obj = rec(value);
  if (obj === null) return;
  for (const [key, raw] of Object.entries(obj)) {
    if (!isElement(key)) continue;
    const isEntry = ENTRY_NAMES.has(localName(key));
    for (const child of Array.isArray(raw) ? raw : [raw]) {
      // root.iter() は entry 自身を返したうえで中も探し続けるので、入れ子の
      // item も拾えるよう先に push してから再帰する。
      if (isEntry) out.push(child);
      collectEntries(child, out);
    }
  }
}

function normalizeFeed(input: string): string[] {
  const found: unknown[] = [];
  collectEntries(JSON.parse(input), found);
  return found.map((value) => JSON.stringify(buildEntry(value)));
}

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
        for (const line of normalizeFeed(input)) console.log(line);
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
