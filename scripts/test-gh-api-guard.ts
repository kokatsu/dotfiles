// test-gh-api-guard.ts — gh-api-guard.ts の判定を gh-api-guard-cases.tsv で固定する。
//
// 引数は shfmt の絶対パス。フック本体と同じく --allow-run をその 1 つに絞る。
// ラッパー (gh-api-guard.sh) を通した経路は scripts/test-gh-api-guard.sh が見る。

import { check } from "../.config/claude/hooks/gh-api-guard.ts";

const shfmt = Deno.args[0];
if (!shfmt) throw new Error("usage: deno test ... -- <path to shfmt>");

interface Case {
  id: string;
  decision: string;
  reason: string;
  command: string;
}

function readCases(): Case[] {
  const text = Deno.readTextFileSync(
    new URL("./gh-api-guard-cases.tsv", import.meta.url),
  );
  return text.split("\n")
    .filter((line) => line !== "" && !line.startsWith("#"))
    .map((line) => {
      const [id, decision, reason, ...rest] = line.split("\t");
      return { id, decision, reason, command: rest.join("\t") };
    });
}

const cases: Case[] = [
  ...readCases(),
  {
    id: "I1",
    decision: "allow",
    reason: "gh api: explicit GET",
    command: "gh ap\\\ni repos/o/r -X GET",
  },
  {
    id: "I2",
    decision: "allow",
    reason: "gh api: explicit GET",
    command: "gh a\\\np\\\ni repos/o/r -X GET",
  },
];

for (const c of cases) {
  Deno.test(`${c.id}: ${c.command}`, async () => {
    const result = await check(c.command, shfmt);
    if (c.decision === "none") {
      if (result !== null) {
        throw new Error(`want no decision, got ${JSON.stringify(result)}`);
      }
      return;
    }
    if (result === null) throw new Error(`want ${c.decision}, got none`);
    if (result.decision !== c.decision || !result.reason.includes(c.reason)) {
      throw new Error(
        `want ${c.decision} / *${c.reason}*, got ${result.decision} / ${result.reason}`,
      );
    }
  });
}
