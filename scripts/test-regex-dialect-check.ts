#!/usr/bin/env -S deno test --allow-read
// test-regex-dialect-check.ts — regex-dialect-check.ts の変換器を直接検証する。
//
// check-regex-dialect.sh は文字クラスの包含と corpus の判定を見るが、corpus は
// 両方言で判定が一致する入力だけなので、包含の向きが変わらない範囲の変換ミスを
// 通してしまう。特に [:alnum:] は corpus のどの行にも現れない。ここでは変換
// 結果そのものと、banned-commands.json の方言を見る。変換後のルールが実際の
// コマンドをどう判定するかは scripts/test-banned-commands.sh がフック越しに見る。

import { toEcmaScript } from "./regex-dialect-check.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertFalse(condition: boolean, message: string): void {
  assert(!condition, message);
}

const RULES_PATH = new URL(
  "../.config/claude/hooks/banned-commands.json",
  import.meta.url,
);

interface Rule {
  pattern: string;
  message: string;
}

function rules(): Rule[] {
  return JSON.parse(Deno.readTextFileSync(RULES_PATH)) as Rule[];
}

Deno.test("[:space:] becomes \\s", () => {
  assertEquals(toEcmaScript("a[[:space:]]+b"), "a[\\s]+b");
});

Deno.test("[:alnum:] becomes A-Za-z0-9, negation included", () => {
  assertEquals(toEcmaScript("([^[:alnum:]_]|$)"), "([^A-Za-z0-9_]|$)");
  assertEquals(toEcmaScript("[[:alnum:]]"), "[A-Za-z0-9]");
});

Deno.test("every rule converts to a pattern with no POSIX class left", () => {
  for (const rule of rules()) {
    const converted = toEcmaScript(rule.pattern);
    assertFalse(
      /\[:[a-z]+:\]/.test(converted),
      `POSIX class survived conversion: ${converted}`,
    );
    new RegExp(converted); // throws if the conversion produced invalid syntax
  }
});

// banned-commands.json の正本方言は POSIX ERE である。ECMAScript 構文へ書き換え
// られても、条件 1 と 2 の包含関係は壊れないので check-regex-dialect.sh では
// 気づけない。方言そのものをここで縛る。
//
// 許可する POSIX クラスを 2 つに限るのは、toEcmaScript() が知っているのがこの
// 2 つだけだからである。3 つ目を JSON へ足すと、変換されないまま RegExp に渡り、
// 文字クラスではなく文字の羅列として黙って別の意味になる。
Deno.test("rules use only the POSIX classes the converter knows", () => {
  const known = new Set(["[:space:]", "[:alnum:]"]);
  for (const rule of rules()) {
    for (const found of rule.pattern.match(/\[:[a-z]+:\]/g) ?? []) {
      assert(
        known.has(found),
        `unknown POSIX class ${found} in: ${rule.pattern}`,
      );
    }
  }
});

// ECMAScript 固有の構文が混ざると、正本が POSIX ERE でなくなる。bash の ERE は
// \s も \d も lookaround も解釈しないので、混ざった時点で両方言で読める状態が
// 失われる。
Deno.test("rules carry no ECMAScript-only syntax", () => {
  const forbidden: [RegExp, string][] = [
    [/\\[sSdDwWbB]/, "a \\s / \\d / \\w style shorthand"],
    [/\(\?[=!<]/, "a lookaround"],
    [/\\[pP]\{/, "a Unicode property escape"],
    [/\\u\{/, "a \\u{...} escape"],
  ];
  for (const rule of rules()) {
    for (const [re, what] of forbidden) {
      assertFalse(re.test(rule.pattern), `${what} in: ${rule.pattern}`);
    }
  }
});
