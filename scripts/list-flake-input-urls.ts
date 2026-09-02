#!/usr/bin/env -S deno run --no-prompt
// list-flake-input-urls.ts — flake.nix のブロック形式 input を `<name> <url>` で列挙する
//
// stdin で flake 本文を受け取り、stdout へ 1 行 1 input を書く。ファイルパスを
// 渡さないので Deno の権限フラグは一つも要らない。
//
// 対象は `<name> = {` の直後に `url = "...";` が続く形だけで、
// `nixpkgs.url = "...";` のような短形式は sync-flake-inputs.sh の従来仕様どおり
// 対象外 (Renovate がタグを書き換えるのはブロック形式の input だけ)。

const BLOCK_INPUT = /^\s+([\w-]+)\s*=\s*\{\s*\n\s+url\s*=\s*"([^"]+)"/gm;

const source = await new Response(Deno.stdin.readable).text();
for (const [, name, url] of source.matchAll(BLOCK_INPUT)) {
  console.log(`${name} ${url}`);
}
