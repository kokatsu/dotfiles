#!/usr/bin/env -S deno run --no-prompt
// regex-dialect-check.ts — check-banned-commands.sh を Deno へ移す準備として、
// banned-commands.json の POSIX ERE を ECMAScript へ変換したときの差を測る。
//
//   space-set      stdout: ECMAScript の \s が一致する符号位置 (U+XXXX、1 行 1 個)
//   match-corpus   argv[1]: banned-commands.json / stdin: 判定したいコマンド行
//                  stdout: "BLOCK<TAB>行" または "allow<TAB>行"
//
// 対になる POSIX 側の走査と突き合わせは check-regex-dialect.sh が行う。
//
// 変換は POSIX の文字クラストークンを 2 つ置き換えるだけである。トークンは必ず
// [ と ] の内側に現れるので、内側だけを置換すれば [[:space:]] は [\s] に、
// [^[:alnum:]_] は [^A-Za-z0-9_] になる。どちらも ECMAScript 側が POSIX 側を
// 包含するため、差は過剰ブロックの向きにしか出ない。逆向きの差が出れば
// check-regex-dialect.sh が失敗する。
export function toEcmaScript(pattern: string): string {
  return pattern
    .replaceAll("[:space:]", "\\s")
    .replaceAll("[:alnum:]", "A-Za-z0-9");
}

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
        "usage: regex-dialect-check.ts {space-set|match-corpus <rules.json>}",
      );
      Deno.exit(2);
  }
}
