// test-transcript-grep-guard.ts — transcript-grep-guard.ts の判定を固定する。
//
// 引数は shfmt の絶対パス。transcript ディレクトリは一時ディレクトリに作り、
// その外を指す symlink と外のファイルも用意する。

import { check } from "../.config/claude/hooks/transcript-grep-guard.ts";

const shfmt = Deno.args[0];
if (!shfmt) throw new Error("usage: deno test ... -- <path to shfmt>");

const root = Deno.makeTempDirSync();
const projects = `${root}/projects`;
Deno.mkdirSync(`${projects}/-home-x`, { recursive: true });
const t = `${projects}/-home-x/s.jsonl`;
Deno.writeTextFileSync(t, "{}\n");
Deno.writeTextFileSync(`${root}/secret.jsonl`, "{}\n");
Deno.symlinkSync(`${root}/secret.jsonl`, `${projects}/-home-x/link.jsonl`);

const allow: string[] = [
  `grep -o -E '.{0,40}pricing\\.md.{0,40}' ${t}`,
  `grep -oE '(a|b)$' ${t}`,
  `grep -c -F 'x' ${t}`,
  `grep -m 3 -e 'Opus 5.5' ${t}`,
  `grep -m3 -e a -e b ${t}`,
  `grep -i "plain words" ${t}`,
  `grep -n x '${t}'`,
];

const none: string[] = [
  `grep -r token ${root} ${t}`,
  `grep -o x ${root}/secret.jsonl ${t}`,
  `grep --filter='jsonl:sh -c id' x ${t}`,
  `grep -P x ${t}`,
  `grep -o x ${t} | head -3`,
  `grep -o x ${t}; id`,
  `grep -o x ${t} && id`,
  `grep -o x ${t} > ${root}/out`,
  `grep -o x ${t} &`,
  `! grep -o x ${t}`,
  `FOO=1 grep -o x ${t}`,
  `grep -o "$(id)" ${t}`,
  `grep -o "$HOME" ${t}`,
  `grep -o $'x' ${t}`,
  `grep -o x ${projects}/-home-x/*.jsonl`,
  `grep -o x ${projects}/../secret.jsonl`,
  `grep -o x ${projects}/-home-x/link.jsonl`,
  `grep -o x ${projects}/-home-x/missing.jsonl`,
  `grep -o x ${projects}/-home-x/s.json`,
  `grep -o x`,
  `grep -m x a ${t}`,
  `grep -e`,
  `command grep -o x ${t}`,
  `ugrep -o x ${t}`,
  `grep -o x ${t} ${t}`,
  `grep -- x ${t}`,
  `grep 'unterminated ${t}`,
];

for (const command of allow) {
  Deno.test(`allow: ${command}`, async () => {
    if (!(await check(command, shfmt, projects))) {
      throw new Error("want allow, got none");
    }
  });
}

for (const command of none) {
  Deno.test(`none: ${command}`, async () => {
    if (await check(command, shfmt, projects)) {
      throw new Error("want none, got allow");
    }
  });
}

// Deno は登録順に走らせるので、最後に登録すれば後片付けになる。
Deno.test("cleanup", () => Deno.removeSync(root, { recursive: true }));
