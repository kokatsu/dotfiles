#!/usr/bin/env -S deno run --no-prompt
// transcript-grep-guard.ts — transcript 1 件だけを読む grep だと証明できたときだけ
// allow を返す PreToolUse フック。証明できなければ何も出さず、通常の権限判定に任せる。
//
// 狙いは Stop の agent hook である。検査役は dontAsk で動き、許可ルールに無い Bash は
// 拒否される。Grep ツールも無く、Read は大きな transcript を先頭から少しずつしか
// 読めないので、直近のツール結果を確かめられない。許可ルール
// `Bash(grep * …/projects/*)` は途中の * に別のファイルや --filter (外部コマンド
// 実行) が入るので使えない。
//
// argv[1] は shfmt、argv[2] は transcript を置くディレクトリ (どちらも絶対パス)。
// ランチャーが解決して渡す。
//
// allow はメインの会話にも効く。過去のセッションの transcript を確認なしで
// grep できるようになる点は承知の上で、範囲をこの形に絞っている。

import { isNode, type Node } from "./shell-words.ts";

// 値を取らない短オプション。束ねてもよい。ugrep の解釈と食い違うと値の位置が
// ずれるので、値を取る文字は入れない。
const BOOL_FLAGS = "acEFino";

// 文とコマンドに現れてよいキー。リダイレクト、代入、&、! などはキーとして
// 現れるので、一覧に無いキーがあれば拒否すれば個別に数え上げずに済む。
const STMT_KEYS = new Set(["Cmd", "End", "Pos", "Position"]);
const CALL_KEYS = new Set(["Args", "End", "Pos", "Type"]);

// 引用の外では glob、brace、チルダ、バックスラッシュが字面を変える。
const UNQUOTED_UNSAFE = /[*?[\]{}~\\]/;

// 展開を含まず、字面がそのまま実引数になる語ならその文字列を返す。
function literal(word: unknown): string | null {
  const parts = isNode(word) && Array.isArray(word.Parts) ? word.Parts : [];
  if (parts.length === 0) return null;
  let text = "";
  for (const part of parts) {
    if (!isNode(part)) return null;
    const value = typeof part.Value === "string" ? part.Value : null;
    switch (part.Type) {
      case "Lit":
        if (value === null || UNQUOTED_UNSAFE.test(value)) return null;
        text += value;
        break;
      case "SglQuoted":
        // $'…' は ANSI-C エスケープを解かないと中身が分からない。
        if (value === null || part.Dollar) return null;
        text += value;
        break;
      case "DblQuoted": {
        const inner = Array.isArray(part.Parts) ? part.Parts : [];
        for (const child of inner) {
          if (!isNode(child) || child.Type !== "Lit") return null;
          const v = typeof child.Value === "string" ? child.Value : null;
          if (v === null || v.includes("\\")) return null;
          text += v;
        }
        break;
      }
      default:
        return null;
    }
  }
  return text;
}

function onlyKeys(node: Node, allowed: Set<string>): boolean {
  return Object.keys(node).every((key) => allowed.has(key));
}

// grep の後ろの実引数から、読むファイルを 1 つだけ取り出す。形が外れたら null。
function targetFile(args: string[]): string | null {
  let patternGiven = false;
  const operands: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "-e") {
      if (i + 1 >= args.length) return null;
      patternGiven = true;
      i += 1;
    } else if (arg === "-m") {
      if (!/^\d+$/.test(args[i + 1] ?? "")) return null;
      i += 1;
    } else if (/^-m\d+$/.test(arg)) {
      continue;
    } else if (arg.startsWith("-")) {
      if (
        arg.length < 2 ||
        ![...arg.slice(1)].every((c) => BOOL_FLAGS.includes(c))
      ) return null;
    } else {
      operands.push(arg);
    }
  }
  const files = patternGiven ? operands : operands.slice(1);
  return files.length === 1 ? files[0] : null;
}

// 実体が transcript ディレクトリの下にある .jsonl か。symlink で外へ
// 出られないよう realPath で比べる。読めなければ (権限外を含め) 偽にする。
function isTranscript(path: string, projectsDir: string): boolean {
  if (!path.startsWith("/") || !path.endsWith(".jsonl")) return false;
  try {
    const root = Deno.realPathSync(projectsDir) + "/";
    const real = Deno.realPathSync(path);
    return real.startsWith(root) && real.endsWith(".jsonl");
  } catch {
    return false;
  }
}

export function decide(ast: unknown, projectsDir: string): boolean {
  if (!isNode(ast) || !Array.isArray(ast.Stmts) || ast.Stmts.length !== 1) {
    return false;
  }
  const stmt = ast.Stmts[0];
  if (!isNode(stmt) || !onlyKeys(stmt, STMT_KEYS)) return false;
  const call = stmt.Cmd;
  if (!isNode(call) || call.Type !== "CallExpr" || !onlyKeys(call, CALL_KEYS)) {
    return false;
  }
  const words = (Array.isArray(call.Args) ? call.Args : []).map(literal);
  if (words.length < 3 || words.some((word) => word === null)) return false;
  const [name, ...args] = words as string[];
  if (name !== "grep") return false;
  const file = targetFile(args);
  return file !== null && isTranscript(file, projectsDir);
}

export async function check(
  command: string,
  shfmt: string,
  projectsDir: string,
): Promise<boolean> {
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
  if (code !== 0) return false;
  return decide(JSON.parse(new TextDecoder().decode(stdout)), projectsDir);
}

async function main(): Promise<void> {
  const [shfmt, projectsDir] = Deno.args;
  const payload = JSON.parse(await new Response(Deno.stdin.readable).text());
  const command = payload?.tool_input?.command;
  if (typeof command !== "string" || !shfmt || !projectsDir) return;
  if (!(await check(command, shfmt, projectsDir))) return;
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: "read-only grep over one transcript",
    },
  }));
}

if (import.meta.main) {
  // 想定外は何も出さずに終わる。通常の権限判定に戻るだけで、許可は増えない。
  await main().catch(() => {});
}
