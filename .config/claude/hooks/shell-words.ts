// shell-words.ts — shfmt --tojson の AST から語とコマンド名を読む共通部分。
// gh-api-guard.ts と transcript-grep-guard.ts が使う。
//
// 同じ読み方の Go 版が tools/claude-bash-guard/words.go にあり、禁止コマンドの
// 判定はそちらが行う。片方の解釈を変えたら、もう片方も揃えること。

// --- shfmt --tojson のノード ---------------------------------------------

export type Node = Record<string, unknown>;

export function isNode(value: unknown): value is Node {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// jq の `..` と同じ前順走査。値を出してから子へ降り、オブジェクトはキー順、
// 配列は要素順で辿る。採用される判定はこの順序の先頭なので、順序自体が仕様。
export function* walk(value: unknown): Generator<Node> {
  if (isNode(value)) {
    yield value;
    for (const child of Object.values(value)) yield* walk(child);
  } else if (Array.isArray(value)) {
    for (const child of value) yield* walk(child);
  }
}

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

// --- 語の展開 -------------------------------------------------------------

const ANSI_TOKEN =
  /\\x[0-9a-fA-F]{1,2}|\\u[0-9a-fA-F]{1,4}|\\U[0-9a-fA-F]{1,8}|\\[0-7]{1,3}|\\[\s\S]|[^\\]+/g;

// BEL/ESC/VT は符号位置から組み立てる。リテラルで書くと deno fmt が生の制御
// 文字に畳み、editorconfig-checker がファイルを binary と判定する。
const ANSI_SHORTHAND: Record<string, string> = {
  n: "\n",
  t: "\t",
  r: "\r",
  a: String.fromCharCode(0x07),
  b: String.fromCharCode(0x08),
  e: String.fromCharCode(0x1b),
  f: String.fromCharCode(0x0c),
  v: String.fromCharCode(0x0b),
};

// $'...' の中身を展開する。範囲外の符号位置では入力文字列をそのまま返す。
function ansiDecode(value: string): string {
  try {
    return (value.match(ANSI_TOKEN) ?? [])
      .map((token) => {
        if (/^\\[xuU]/.test(token)) {
          return String.fromCodePoint(parseInt(token.slice(2), 16));
        }
        if (/^\\[0-7]/.test(token)) {
          return String.fromCodePoint(parseInt(token.slice(1), 8));
        }
        if (token.startsWith("\\")) {
          return ANSI_SHORTHAND[token.slice(1)] ?? token.slice(1);
        }
        return token;
      })
      .join("");
  } catch {
    return value;
  }
}

// AST の語を文字列に戻す。展開結果が分からない部分 (ParamExp、CmdSubst など) は
// 空文字になるので、`"$x"rm` は `rm` として読まれる。Lit はバックスラッシュを
// すべて落とすため `r\m` も `rm` になる。取りこぼすより過剰に一致させる側へ倒す。
export function wordText(word: unknown): string {
  if (!isNode(word)) return "";
  const parts = Array.isArray(word.Parts) ? word.Parts : [];
  return parts
    .map((part): string => {
      if (!isNode(part)) return "";
      switch (part.Type) {
        case "Lit":
          return str(part.Value).replaceAll("\\", "");
        case "SglQuoted":
          return part.Dollar ? ansiDecode(str(part.Value)) : str(part.Value);
        case "DblQuoted": {
          const inner = Array.isArray(part.Parts) ? part.Parts : [];
          return inner
            .map((p) => (isNode(p) && p.Type === "Lit" ? str(p.Value) : ""))
            .join("");
        }
        default:
          return "";
      }
    })
    .join("");
}

// jq の [[:space:]] は U+0085 に一致し、JavaScript の \s は一致しない。sSplit の
// 区切り判定がこの集合を包含していないと env -S の引数を取りこぼす。
// Go 版の rules.JQSpaceClass と同じ集合で、包含は scripts/check-regex-dialect.sh
// が Go 側で検査する。
const JQ_SPACE = "\\s\\u0085";

// env -S の値の分割を模す。空白と引用符外の \_ が引数区切りで、"..." と '...' の
// 引用とバックスラッシュエスケープを解く。ダブルクォート内の \_ は引数内の空白に
// なる。区切りもトークンとして取り出してから捨てることで、\_ の _ が次の語へ
// 接着するのを防ぐ。展開結果は env のオプションとして読み直す。
const S_SPLIT_TOKEN = new RegExp(
  `\\\\_|[${JQ_SPACE}]+|(?:[^${JQ_SPACE}"'\\\\]|\\\\[^_]|"(?:[^"\\\\]|\\\\[\\s\\S])*"|'[^']*')+`,
  "g",
);

const S_SPLIT_SEPARATOR = new RegExp(`^(\\\\_|[${JQ_SPACE}]+)$`);

function sSplit(value: string): string[] {
  return (value.match(S_SPLIT_TOKEN) ?? [])
    .filter((token) => !S_SPLIT_SEPARATOR.test(token))
    .map((token) =>
      token
        .replace(/"((?:[^"\\]|\\[\s\S])*)"/g, (_m, q: string) =>
          q.replaceAll("\\_", " "))
        .replace(/'([^']*)'/g, (_m, q: string) =>
          q)
        .replace(/\\([\s\S])/g, (_m, c: string) => c)
    );
}

// --- オプション列の走査 ---------------------------------------------------

// 短オプションは束ねられる ("sudo -nu root")。左から見て、値を取る文字が末尾に
// あれば次の語を食べ、途中にあれば残りが付属値になる。
function clusterEats(cluster: string, argChars: string): boolean {
  if (cluster.length === 0) return false;
  const c = cluster[0];
  if (argChars.includes(c)) return cluster.length === 1;
  return clusterEats(cluster.slice(1), argChars);
}

// 束の中に -v/-V があるとコマンドを実行しなくなるので、純粋な -p の束だけ剥がす。
// "--" の次はオプションに見えてもコマンド名なので、そこで剥がすのをやめる。
function stripCommandOpts(args: string[]): string[] {
  if (args.length === 0) return args;
  if (args[0] === "--") return args.slice(1);
  if (/^-p+$/.test(args[0])) return stripCommandOpts(args.slice(1));
  return args;
}

function stripEnvOpts(args: string[]): string[] {
  if (args.length === 0) return args;
  const head = args[0];
  if (
    head === "-u" || head === "-C" || head === "--unset" || head === "--chdir"
  ) {
    return stripEnvOpts(args.slice(2));
  }
  if (head === "-S" || head === "--split-string") {
    return stripEnvOpts([...sSplit(args[1] ?? ""), ...args.slice(2)]);
  }
  if (head.startsWith("--split-string=")) {
    return stripEnvOpts([...sSplit(head.slice(15)), ...args.slice(1)]);
  }
  const attached = /^-[i0v]*S(.*)$/.exec(head);
  if (attached) {
    return attached[1] === ""
      ? stripEnvOpts([...sSplit(args[1] ?? ""), ...args.slice(2)])
      : stripEnvOpts([...sSplit(attached[1]), ...args.slice(1)]);
  }
  if (/^-[A-Za-z0]+$/.test(head)) {
    return stripEnvOpts(args.slice(clusterEats(head.slice(1), "uC") ? 2 : 1));
  }
  if (/^-/.test(head) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(head)) {
    return stripEnvOpts(args.slice(1));
  }
  return args;
}

const SUDO_VALUE_OPTS = new Set([
  "--chdir",
  "--chroot",
  "--close-from",
  "--command-timeout",
  "--group",
  "--host",
  "--other-user",
  "--prompt",
  "--role",
  "--type",
  "--user",
]);

function stripSudoOpts(args: string[]): string[] {
  if (args.length === 0) return args;
  const head = args[0];
  if (head === "--") return args.slice(1);
  if (SUDO_VALUE_OPTS.has(head)) return stripSudoOpts(args.slice(2));
  if (/^-[A-Za-z]+$/.test(head)) {
    return stripSudoOpts(
      args.slice(clusterEats(head.slice(1), "aCDghprRtTuU") ? 2 : 1),
    );
  }
  if (/^-/.test(head) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(head)) {
    return stripSudoOpts(args.slice(1));
  }
  return args;
}

function stripExecOpts(args: string[]): string[] {
  if (args.length === 0) return args;
  const head = args[0];
  if (head === "--") return args.slice(1);
  if (/^-[A-Za-z]+$/.test(head)) {
    return stripExecOpts(args.slice(clusterEats(head.slice(1), "a") ? 2 : 1));
  }
  if (/^-/.test(head)) return stripExecOpts(args.slice(1));
  return args;
}

export function stripWrappers(args: string[]): string[] {
  if (args.length === 0) return args;
  switch (args[0]) {
    case "command":
      return stripWrappers(stripCommandOpts(args.slice(1)));
    case "env":
      return stripWrappers(stripEnvOpts(args.slice(1)));
    case "sudo":
    case "doas":
      return stripWrappers(stripSudoOpts(args.slice(1)));
    case "exec":
      return stripWrappers(stripExecOpts(args.slice(1)));
    case "builtin": {
      const rest = args.slice(1);
      return stripWrappers(
        rest.length > 0 && rest[0] === "--" ? rest.slice(1) : rest,
      );
    }
    default:
      return args;
  }
}
