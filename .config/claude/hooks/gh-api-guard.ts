#!/usr/bin/env -S deno run --no-prompt
// gh-api-guard.ts — `gh api` が読み取りだと証明できたときだけ allow を返す
// PreToolUse フック。証明できなければ ask へ落とす。
//
// argv[1] は shfmt の絶対パス。ランチャーが command -v で解決して渡す。
//
// 判定は生文字列ではなく shfmt --tojson の AST の argv に対して行う。値の中身が
// 旗に見えるだけの読み取り (`--jq '… -X DELETE …'`) を ask にせず、展開が旗を
// 持ち込める形 (`gh api "$@"`) を allow にしないためである。
//
// settings.json の `if: "Bash(gh api *)"` が入口なので、このフックが走る時点で
// `gh api` があるか、Claude Code がコマンドを解析できなかったかのどちらかである。
// 後者では gh api の無い入力も届くため、何も出さずに 0 で終わる経路を残す。

import {
  isNode,
  type Node,
  stripWrappers,
  walk,
  wordText,
} from "./check-banned-commands.ts";

// gh api の短オプション。値を取る文字を取り違えると束の解釈が壊れる。真偽値を
// 値を取る側に入れると `-iF a=b` の F が i に食われて POST が素通りするので、
// `gh api --help` が値を取ると書いている文字だけを入れる。
const SHORT_VALUE = "FHXqpft";
const SHORT_BOOL = "i";
const SHORT_BODY = "Ff";

const LONG_VALUE = new Set([
  "cache",
  "field",
  "header",
  "hostname",
  "input",
  "jq",
  "method",
  "preview",
  "raw-field",
  "template",
]);
const LONG_BOOL = new Set([
  "allow-escape-sequences",
  "help",
  "include",
  "paginate",
  "silent",
  "slurp",
  "verbose",
]);
const LONG_BODY = new Set(["field", "input", "raw-field"]);

const BODY_REASON =
  "gh api: body-bearing flag (-f/-F/--field/--raw-field/--input) implies POST";
const NON_LITERAL_REASON =
  "gh api: an expanded argument could add a flag — confirm intent";
const INDIRECT_REASON =
  "gh api: indirect invocation (eval / sh -c / xargs) — confirm intent";
const UNREADABLE_REASON =
  "gh api: an expanded word hides what runs — confirm intent";
const UNPARSED_REASON =
  "gh api: could not parse this command as bash — confirm intent";
const ALLOW_REASON = "gh api: read-only (GET/HEAD)";

function methodReason(verb: string | null): string {
  return `gh api: HTTP method override to '${
    verb ?? "?"
  }' (not GET/HEAD) — confirm intent`;
}

// 語分割を起こす部分。引用の外の展開はすべて、引用の中でも "$@" と添字つきは
// 複数語に増える。`"repos/${a[@]}"` は字面で始まっても 2 語目に旗を置ける。
function splitsWords(part: Node): boolean {
  const type = String(part.Type ?? "");
  if (type === "Lit" || type === "SglQuoted") return false;
  if (type !== "DblQuoted") return true;
  const inner = Array.isArray(part.Parts) ? part.Parts : [];
  return inner.some((child) => {
    if (!isNode(child)) return true;
    if (child.Type !== "ParamExp") return splitsWords(child);
    const name = isNode(child.Param) ? String(child.Param.Value ?? "") : "";
    return name === "@" || name === "*" || child.Index !== undefined;
  });
}

// 展開せずに読める先頭の字面と、その部分が最後まで読めたか。バックスラッシュは
// 落とさない。`-X\ GET` の実引数は `-X GET` だが、ここでは `-X\ GET` のまま GET と
// 一致せず ask になる。落とすと `-\X DELETE` が旗として読めてしまう。
function literalPrefix(part: Node): { text: string; complete: boolean } {
  switch (part.Type) {
    case "Lit":
      return typeof part.Value === "string"
        ? { text: part.Value, complete: true }
        : { text: "", complete: false };
    case "SglQuoted":
      // $'…' は ANSI-C エスケープを解かないと中身が分からない。解かないので不明。
      return !part.Dollar && typeof part.Value === "string"
        ? { text: part.Value, complete: true }
        : { text: "", complete: false };
    case "DblQuoted": {
      const inner = Array.isArray(part.Parts) ? part.Parts : [];
      let text = "";
      for (const child of inner) {
        if (!isNode(child)) return { text, complete: false };
        const read = literalPrefix(child);
        text += read.text;
        if (!read.complete) return { text, complete: false };
      }
      return { text, complete: true };
    }
    default:
      return { text: "", complete: false };
  }
}

interface Word {
  // 全体が字面なら展開後の文字列、展開を含むなら null。
  literal: string | null;
  // 最初の展開より前の字面。展開で始まる語では空文字になる。
  prefix: string;
  splittable: boolean;
}

function readWord(word: unknown): Word {
  const parts = isNode(word) && Array.isArray(word.Parts) ? word.Parts : [];
  let literal: string | null = "";
  let prefix = "";
  let knownSoFar = true;
  let splittable = false;

  for (const part of parts) {
    if (!isNode(part)) {
      literal = null;
      knownSoFar = false;
      splittable = true;
      continue;
    }
    if (splitsWords(part)) splittable = true;
    const read = literalPrefix(part);
    if (knownSoFar) prefix += read.text;
    if (read.complete) {
      if (literal !== null) literal += read.text;
    } else {
      literal = null;
      knownSoFar = false;
    }
  }
  return { literal, prefix, splittable };
}

function isReadOnlyVerb(verb: string | null): boolean {
  return verb !== null && /^(get|head)$/i.test(verb);
}

// 束ねられた短オプションを左から解く。値を取る文字が現れたら束の残りが値になり、
// 残りが空なら次の語を食う。
function shortCluster(
  cluster: string,
  next: Word | undefined,
): { reason: string | null; eatsNext: boolean; valueTaken: boolean } {
  for (let i = 0; i < cluster.length; i++) {
    const letter = cluster[i];
    if (SHORT_BOOL.includes(letter)) continue;
    if (!SHORT_VALUE.includes(letter)) {
      return {
        reason: `gh api: unknown flag '-${letter}' — confirm intent`,
        eatsNext: false,
        valueTaken: false,
      };
    }
    if (SHORT_BODY.includes(letter)) {
      return { reason: BODY_REASON, eatsNext: false, valueTaken: true };
    }
    const glued = cluster.slice(i + 1);
    if (letter !== "X") {
      return { reason: null, eatsNext: glued === "", valueTaken: true };
    }
    const verb = glued !== "" ? glued : next?.literal ?? null;
    return {
      reason: isReadOnlyVerb(verb) ? null : methodReason(verb),
      eatsNext: glued === "",
      valueTaken: true,
    };
  }
  return { reason: null, eatsNext: false, valueTaken: false };
}

// 展開を含む語。語分割が起きず、字面で読めた頭が旗でなければオペランドであり、
// 展開しても旗にはならない。旗なら、読めた頭から旗を見分けて理由を具体化する。
// 値を取る旗まで読めていれば展開はその値にしかならないので、そこで安全になる。
function nonLiteralReason(word: Word): string | null {
  if (word.splittable || word.prefix === "") return NON_LITERAL_REASON;
  if (!word.prefix.startsWith("-")) return null;

  if (word.prefix.startsWith("--")) {
    const equals = word.prefix.indexOf("=");
    const name = equals < 0
      ? word.prefix.slice(2)
      : word.prefix.slice(2, equals);
    if (LONG_BODY.has(name)) return BODY_REASON;
    if (name === "method") return methodReason(null);
    return LONG_VALUE.has(name) || LONG_BOOL.has(name)
      ? null
      : NON_LITERAL_REASON;
  }

  const cluster = shortCluster(word.prefix.slice(1), undefined);
  if (cluster.reason !== null) return cluster.reason;
  // 真偽値の文字だけで字面が尽きた。展開が X や F を足せる。
  return cluster.valueTaken ? null : NON_LITERAL_REASON;
}

// gh api の後ろの argv を歩き、読み取りと証明できなければ理由を返す。
function argvReason(words: Word[]): string | null {
  let endOfOptions = false;

  // 旗の値として次の語を飲み込むとき、その語が語分割を起こすなら飲み込めない。
  // `-H $H` は H="x -X DELETE" なら 3 語に増え、値の後ろに旗が残る。
  const eats = (index: number): boolean => !words[index + 1]?.splittable;

  for (let i = 0; i < words.length; i++) {
    const word = words[i];

    if (word.literal === null) {
      if (endOfOptions) continue;
      const reason = nonLiteralReason(word);
      if (reason !== null) return reason;
      continue;
    }

    const text = word.literal;
    if (endOfOptions || !text.startsWith("-") || text === "-") continue;
    if (text === "--") {
      endOfOptions = true;
      continue;
    }

    if (text.startsWith("--")) {
      const equals = text.indexOf("=");
      const name = equals < 0 ? text.slice(2) : text.slice(2, equals);
      if (LONG_BODY.has(name)) return BODY_REASON;
      if (!LONG_VALUE.has(name) && !LONG_BOOL.has(name)) {
        return `gh api: unknown flag '--${name}' — confirm intent`;
      }
      const glued = equals < 0 ? null : text.slice(equals + 1);
      if (name === "method") {
        const verb = glued ?? words[i + 1]?.literal ?? null;
        if (!isReadOnlyVerb(verb)) return methodReason(verb);
      }
      if (LONG_VALUE.has(name) && glued === null) {
        if (!eats(i)) return NON_LITERAL_REASON;
        i += 1;
      }
      continue;
    }

    const { reason, eatsNext } = shortCluster(text.slice(1), words[i + 1]);
    if (reason !== null) return reason;
    if (eatsNext) {
      if (!eats(i)) return NON_LITERAL_REASON;
      i += 1;
    }
  }

  return null;
}

// gh api を自分の argv の外へ隠している呼び出し。中身を読めないので ask にする。
function hidesGhApi(texts: string[]): boolean {
  return texts.some((text, index) =>
    /\bgh\s+api\b/.test(text) || (text === "gh" && texts[index + 1] === "api")
  );
}

interface Decision {
  decision: "allow" | "ask";
  reason: string;
}

export function decide(ast: unknown): Decision | null {
  let seen = false;
  let reason: string | null = null;

  for (const node of walk(ast)) {
    if (node.Type !== "CallExpr") continue;
    const args = Array.isArray(node.Args) ? node.Args : [];
    if (args.length === 0) continue;
    const words = args.map(readWord);
    const texts = args.map(wordText);
    const stripped = stripWrappers(texts);
    const offset = texts.length - stripped.length;

    // wordText は展開を空文字へ潰すので、剥がす語数も何のコマンドかも、読めない
    // 語をまたいだ時点で当てにならない。`env -u $V gh api r` は V が 2 語以上へ
    // 割れれば別のコマンドを走らせるし、`$CMD api r -X DELETE` の頭は gh になりうる。
    if (words.slice(0, offset + 1).some((word) => word.literal === null)) {
      reason ??= UNREADABLE_REASON;
      continue;
    }

    if (stripped[0] === "gh" && stripped[1] === "api") {
      seen = true;
      reason ??= argvReason(words.slice(offset + 2));
      continue;
    }
    if (hidesGhApi(stripped)) reason ??= INDIRECT_REASON;
  }

  if (reason !== null) return { decision: "ask", reason };
  return seen ? { decision: "allow", reason: ALLOW_REASON } : null;
}

const GH_API_TEXT = /\bgh\s+api\b/;

function emit(result: Decision): void {
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: result.decision,
      permissionDecisionReason: result.reason,
    },
  }));
}

async function main(): Promise<void> {
  const shfmt = Deno.args[0] || "shfmt";
  const payload = JSON.parse(await new Response(Deno.stdin.readable).text());
  const command = payload?.tool_input?.command;
  if (typeof command !== "string") {
    return emit({ decision: "ask", reason: UNPARSED_REASON });
  }

  // shfmt は stdin だけで動くので環境変数を渡さない。渡すと Deno が
  // LD_LIBRARY_PATH の継承に --allow-env まで要求する。
  const run = new Deno.Command(shfmt, {
    args: ["--tojson"],
    clearEnv: true,
    stdin: "piped",
    stdout: "piped",
    stderr: "null",
  }).spawn();
  const writer = run.stdin.getWriter();
  await writer.write(new TextEncoder().encode(command + "\n"));
  await writer.close();
  const { code, stdout } = await run.output();

  if (code !== 0) {
    // 解析できないコマンドにも if ゲートは反応する。gh api が見当たらなければ
    // 判定する対象が無いので黙って通す。
    if (GH_API_TEXT.test(command)) {
      emit({ decision: "ask", reason: UNPARSED_REASON });
    }
    return;
  }

  const result = decide(JSON.parse(new TextDecoder().decode(stdout)));
  if (result !== null) emit(result);
}

if (import.meta.main) {
  try {
    await main();
  } catch {
    // 想定外は ask へ倒す。allow を出すのはこのフックだけなので、黙って終わると
    // 通常の確認へ戻るだけで済む。
    emit({ decision: "ask", reason: UNPARSED_REASON });
  }
}
