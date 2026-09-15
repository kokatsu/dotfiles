#!/usr/bin/env -S deno run --no-prompt
// regex-dialect-check.ts — banned-commands.json の POSIX ERE を ECMAScript へ
// 変換したときの差を測る。check-regex-dialect.sh が使う ECMAScript 側の半分。
//
//   space-set      stdout: ECMAScript の \s が一致する符号位置 (U+XXXX、1 行 1 個)
//   jq-space-set   stdout: フックの JQ_SPACE が一致する符号位置 (同上)
//   match-corpus   argv[1]: banned-commands.json / stdin: 判定したいコマンド行
//                  stdout: "BLOCK<TAB>行" または "allow<TAB>行"
//
// 対になる POSIX 側の走査と突き合わせは check-regex-dialect.sh が行う。
//
// 変換器はフックが持つ。ここで複製すると、実際に使われる方と検査する方が
// 別々に腐る。
export {
  JQ_SPACE,
  toEcmaScript,
} from "../.config/claude/hooks/check-banned-commands.ts";
import {
  JQ_SPACE,
  toEcmaScript,
} from "../.config/claude/hooks/check-banned-commands.ts";

interface Rule {
  pattern: string;
  message: string;
}

function spaceSet(): void {
  const lines: string[] = [];
  for (let cp = 0; cp <= 0xffff; cp++) {
    if (/\s/.test(String.fromCodePoint(cp))) {
      lines.push(`U+${cp.toString(16).toUpperCase().padStart(4, "0")}`);
    }
  }
  console.log(lines.join("\n"));
}

// フックが実際に使っている JQ_SPACE で走査する。ここに定数を書き写すと、
// フック側を \s へ戻しても検査だけが通ってしまう。
function jqSpaceSet(): void {
  const cls = new RegExp(`[${JQ_SPACE}]`);
  const lines: string[] = [];
  for (let cp = 0; cp <= 0xffff; cp++) {
    if (cp >= 0xd800 && cp <= 0xdfff) continue;
    if (cls.test(String.fromCodePoint(cp))) {
      lines.push(`U+${cp.toString(16).toUpperCase().padStart(4, "0")}`);
    }
  }
  console.log(lines.join("\n"));
}

async function matchCorpus(rulesPath: string): Promise<void> {
  const rules = JSON.parse(Deno.readTextFileSync(rulesPath)) as Rule[];
  const regexes = rules.map((r) => new RegExp(toEcmaScript(r.pattern)));
  const input = await new Response(Deno.stdin.readable).text();
  for (const line of input.split("\n")) {
    if (line === "") continue;
    console.log(
      `${regexes.some((re) => re.test(line)) ? "BLOCK" : "allow"}\t${line}`,
    );
  }
}

if (import.meta.main) {
  const [subcommand, ...rest] = Deno.args;
  switch (subcommand) {
    case "space-set":
      spaceSet();
      break;
    case "jq-space-set":
      jqSpaceSet();
      break;
    case "match-corpus":
      if (rest.length !== 1) {
        console.error(
          "usage: regex-dialect-check.ts match-corpus <banned-commands.json>",
        );
        Deno.exit(2);
      }
      await matchCorpus(rest[0]);
      break;
    default:
      console.error(
        "usage: regex-dialect-check.ts {space-set|jq-space-set|match-corpus <rules.json>}",
      );
      Deno.exit(2);
  }
}
