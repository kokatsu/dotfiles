#!/usr/bin/env -S deno run --no-prompt
// check-banned-commands.ts — PreToolUse hook の判定部。ランチャーの
// check-banned-commands.sh から stdin で hook payload を受け取り、ブロックする
// なら理由を stderr に出して exit 2 で終わる。
//
// argv[1] は shfmt の絶対パス。ランチャーが command -v で解決して渡す。
//
// 判定は 2 系統ある。banned-commands.json のテキストパターンは、単一の
// CallExpr に紐づけられない形 (パイプ先、リダイレクト先、代入の前置) を見る。
// コマンド名に紐づく規則は shfmt --tojson の AST を歩いて見る。区切り文字の
// 正規表現では改行・then/do・ラッパー・バッククォートを覆えないためである。
//
// 採用するのは最初の判定 1 つだけで、その順序は scripts/verdict-precedence-cases.txt
// が固定している。GIT_AUTHOR_*/GIT_COMMITTER_* 由来の 2 系統はコマンド中の位置に
// 関係なく先行し、コマンドごとの判定だけが AST の文書順で決まる。
//
// パースできないときは exit 2 で落ちる。検査できていないコマンドを通さない。

// banned-commands.json の正本方言は POSIX ERE である。実行時に読むのは今この
// TypeScript だけだが、JSON を ECMAScript 構文へ書き換えないこと。RegExp は
// bracket expression を解釈しないので、渡す前にここを通す。
//
// toEcmaScript() は POSIX 側の禁止対象を取りこぼさない向きへ変換する。
// scripts/check-regex-dialect.sh が両方言の包含を測り、
// scripts/test-regex-dialect-check.ts がこの関数と JSON の構文方針を検証する。
export function toEcmaScript(pattern: string): string {
  return pattern
    .replaceAll("[:space:]", "\\s")
    .replaceAll("[:alnum:]", "A-Za-z0-9");
}

export type Verdict =
  | "RM"
  | "EVAL"
  | "SHRED"
  | "PKILL_F"
  | "KILLALL"
  | "MKFS"
  | "DD_DEV"
  | "CHMOD_R_777"
  | "CHMOD_777_ROOT"
  | "GREP_R"
  | "FORCE_PUSH"
  | "GIT_CLEAN"
  | "GIT_RESET_HARD"
  | "SHALLOW"
  | "GIT_IDENTITY"
  | "EXTDIFF";

export const VERDICT_MESSAGES: Record<Verdict, string> = {
  RM: "Use gomi instead of rm",
  EVAL: "Refuse eval. Review the command and run it directly instead.",
  SHRED: "Refuse shred. Confirm intent and run manually.",
  PKILL_F:
    "Refuse pkill -f: it pattern-matches every command line, including this harness and its live servers. Kill by a recorded PID or use the tool's own stop command.",
  KILLALL:
    "Refuse killall. Kill by a recorded PID or use the tool's own stop command.",
  MKFS: "Refuse mkfs. Run manually if intentional.",
  DD_DEV: "Refuse dd writing to a device. Run manually if intentional.",
  CHMOD_R_777: "Refuse chmod -R 777. Use a tighter mode.",
  CHMOD_777_ROOT: "Refuse chmod 777 /. Scope the path.",
  GREP_R:
    "Use rg instead of grep -r/-R (recursive grep). rg respects .gitignore and ~/.ripgreprc glob excludes.",
  FORCE_PUSH:
    "Refuse git push -f/--force. Use --force-with-lease or run manually.",
  GIT_CLEAN:
    "Refuse git clean -fd/-fx (destructive). Inspect untracked files first.",
  GIT_RESET_HARD:
    "Refuse git reset --hard to a remote/historical ref. Confirm intent and run manually.",
  SHALLOW:
    "Refuse shallow git fetch/pull (--depth/--shallow-*) because it makes the existing repository shallow. Use a temporary shallow clone (git clone --depth), or fetch normally. --deepen/--unshallow remain allowed.",
  GIT_IDENTITY:
    "Don't set or override Git identity. ~/.config/git/config.local resolves it per directory via includeIf, and user.useConfigOnly makes Git fail loudly where no entry matches. Ask the user instead of choosing a value.",
  EXTDIFF:
    "Add --no-ext-diff to git diff/show/log -p. The global git config sets diff.external=difft, which mangles diff output when captured as tool output; --no-ext-diff is the only reliable bypass (an empty diff.external= override errors out).",
};

// --- shfmt --tojson のノード ---------------------------------------------

type Node = Record<string, unknown>;

function isNode(value: unknown): value is Node {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// jq の `..` と同じ前順走査。値を出してから子へ降り、オブジェクトはキー順、
// 配列は要素順で辿る。採用される判定はこの順序の先頭なので、順序自体が仕様。
function* walk(value: unknown): Generator<Node> {
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
// この差が禁止判定を変えないことは scripts/test-banned-commands.sh が固定している。
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
function wordText(word: unknown): string {
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
// scripts/check-regex-dialect.sh が包含を検査する。
export const JQ_SPACE = "\\s\\u0085";

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

function stripWrappers(args: string[]): string[] {
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

const GIT_GLOBAL_VALUE_OPTS = new Set([
  "-C",
  "-c",
  "--git-dir",
  "--work-tree",
  "--namespace",
  "--config-env",
]);

function skipGitGlobals(args: string[]): string[] {
  if (args.length === 0) return args;
  if (GIT_GLOBAL_VALUE_OPTS.has(args[0])) return skipGitGlobals(args.slice(2));
  if (args[0].startsWith("-")) return skipGitGlobals(args.slice(1));
  return args;
}

function hasFlag(args: string[], flags: string[]): boolean {
  return args.some((a) => flags.some((f) => a === f || a.startsWith(f + "=")));
}

// 短オプション束のフラグ文字を、最初の値を取る文字まで読む。"git clean -fed" の
// "d" は -e の付属値でありフラグではない。英数字以外も走査を止めるので、
// 付属値に記号が入っていても ("-fofoo-bar") 手前のフラグは隠せない。
function clusterFlags(cluster: string, argChars: string): string {
  if (cluster.length === 0) return "";
  const c = cluster[0];
  if (argChars.includes(c) || !/[A-Za-z0-9]/.test(c)) return "";
  return c + clusterFlags(cluster.slice(1), argChars);
}

// pathspec 区切りの "--" までを歩く。値を別に取るオプションの値を先に落とすので、
// 値そのものが "--" でも区切りとは読まれない ("git clean -e -- -fd")。
function gitOpts(
  args: string[],
  valOpts: string[],
  argChars: string,
): string[] {
  if (args.length === 0) return [];
  const head = args[0];
  if (valOpts.includes(head)) {
    return [head, ...gitOpts(args.slice(2), valOpts, argChars)];
  }
  if (/^-[A-Za-z0-9]/.test(head) && clusterEats(head.slice(1), argChars)) {
    return [head, ...gitOpts(args.slice(2), valOpts, argChars)];
  }
  if (head === "--") return [];
  return [head, ...gitOpts(args.slice(1), valOpts, argChars)];
}

// オプションの走査は "--" で止まる。"-R" という名前のファイルはフラグに見えない。
function optsBeforeDdash(args: string[]): string[] {
  const end = args.indexOf("--");
  return end === -1 ? args : args.slice(0, end);
}

// GNU getopt_long と git parse-options は曖昧でない限り長オプションの前置を
// 受け付ける ("--rec" は --recursive)。付属した =value は比較前に落とす。
function isAbbrevOf(token: string, full: string, minLen: number): boolean {
  const t = token.replace(/=.*$/, "");
  return t.length >= minLen && full.startsWith(t);
}

// --- grep ----------------------------------------------------------------

// "--" でオプションが終わる。-e/-f (パターン) と -d/-D (動作) の値はデータなので、
// 別語でも付属でも束の末尾でも読み飛ばす。束の中でそれらより前に現れた r/R だけが
// 再帰を意味する。数字は束に残す ("-n2r" は文脈行数つきの再帰)。
function grepClusterVerdict(
  cluster: string,
): "plain" | "recursive" | "eats_next" {
  if (cluster.length === 0) return "plain";
  if (/[rR]/.test(cluster[0])) return "recursive";
  if (/[efdD]/.test(cluster[0])) {
    return cluster.length === 1 ? "eats_next" : "plain";
  }
  return grepClusterVerdict(cluster.slice(1));
}

function grepRecursive(args: string[]): boolean {
  if (args.length === 0) return false;
  const head = args[0];
  if (head === "--") return false;
  if (
    isAbbrevOf(head, "--recursive", 5) ||
    isAbbrevOf(head, "--dereference-recursive", 5)
  ) {
    return true;
  }
  if (
    !head.includes("=") &&
    (isAbbrevOf(head, "--regexp", 5) ||
      head === "--file" ||
      isAbbrevOf(head, "--devices", 5) ||
      isAbbrevOf(head, "--directories", 5))
  ) {
    return grepRecursive(args.slice(2));
  }
  if (/^-[A-Za-z0-9]+$/.test(head)) {
    const verdict = grepClusterVerdict(head.slice(1));
    if (verdict === "recursive") return true;
    return grepRecursive(args.slice(verdict === "eats_next" ? 2 : 1));
  }
  return grepRecursive(args.slice(1));
}

// --- git identity ---------------------------------------------------------

// identity は ~/.config/git/config.local の includeIf が決め、合致しなければ
// user.useConfigOnly が失敗させる。リポジトリごとに設定するものは何もない。
// セクションとキーは大文字小文字を区別しない。
function isIdentityKey(token: string): boolean {
  const t = token.toLowerCase();
  return t === "user.email" || t === "user.name";
}

function isIdentityAssignment(token: string): boolean {
  const t = token.toLowerCase();
  return t.startsWith("user.email=") || t.startsWith("user.name=");
}

const CONFIG_VALUE_OPTS = new Set([
  "-f",
  "--file",
  "--blob",
  "-t",
  "--type",
  "--default",
  "--comment",
  "--value",
]);

// git config の、値を別語で取るオプションを落とす。その値をキーや書き込みの印と
// 取り違えないようにする。
function configOperands(args: string[]): string[] {
  if (args.length === 0) return [];
  if (CONFIG_VALUE_OPTS.has(args[0])) return configOperands(args.slice(2));
  if (args[0].startsWith("-")) return configOperands(args.slice(1));
  return [args[0], ...configOperands(args.slice(1))];
}

// 書き込みは identity キーの後ろに値があるか ("git config user.email x"、
// "git config set user.email x")、削除・追加のオプションで名指しされた場合。
// キーの後ろに何もなければ読み取り ("git config --get user.email")。
function configIdentityWrite(rest: string[]): boolean {
  const ops = configOperands(rest);
  const i = ops.findIndex(isIdentityKey);
  if (i === -1) return false;
  const head = (ops[0] ?? "").toLowerCase();
  return (
    ["set", "add", "unset", "unset-all", "replace-all"].includes(head) ||
    rest.some((a) =>
      ["--unset", "--unset-all", "--replace-all", "--add"].includes(a)
    ) ||
    ops.length > i + 1
  );
}

// git -c user.email=... と --config-env=user.email=VAR は一回の実行だけ identity を
// 変える。skipGitGlobals がオプションと値を落とす前に見る。
function gitGlobalIdentity(args: string[]): boolean {
  if (args.length === 0) return false;
  const head = args[0];
  if (head === "-c" || head === "--config-env") {
    return isIdentityAssignment(args[1] ?? "") ||
      gitGlobalIdentity(args.slice(2));
  }
  const lower = head.toLowerCase();
  if (lower.startsWith("-cuser.email=") || lower.startsWith("-cuser.name=")) {
    return true;
  }
  if (head.startsWith("--config-env=")) {
    return isIdentityAssignment(head.slice(13)) ||
      gitGlobalIdentity(args.slice(1));
  }
  if (head.startsWith("-")) return gitGlobalIdentity(args.slice(1));
  return false;
}

// --- git サブコマンド -----------------------------------------------------

interface ValueOpts {
  opts: string[];
  chars: string;
}

// diff/show/log の一覧は実際の git で確認した、値を「別語で」取るものだけ。
// 単独で有効なもの (-U、--unified、--pretty、--format) や = 必須のもの
// (--date、--max-count、--skip、-l) を入れてはいけない。入れると本物の "--" を
// 食べてしまう。
function valueOptsFor(sub: string): ValueOpts {
  switch (sub) {
    case "clean":
      return { opts: ["-e", "--exclude"], chars: "e" };
    case "fetch":
    case "pull":
      return {
        opts: [
          "--upload-pack",
          "-o",
          "--server-option",
          "--negotiation-tip",
          "--refmap",
          "-j",
          "--jobs",
          "--depth",
          "--shallow-since",
          "--shallow-exclude",
        ],
        chars: "jo",
      };
    case "push":
      return {
        opts: ["--receive-pack", "--exec", "--repo", "-o", "--push-option"],
        chars: "o",
      };
    case "diff":
    case "show":
    case "log":
      return {
        opts: [
          "-G",
          "-S",
          "-O",
          "-n",
          "-L",
          "--since",
          "--until",
          "--author",
          "--committer",
          "--grep",
          "--output",
          "--rotate-to",
          "--skip-to",
          "--find-object",
          "--decorate-refs",
          "--decorate-refs-exclude",
        ],
        chars: "GSOnL",
      };
    default:
      return { opts: [], chars: "" };
  }
}

function gitVerdict(args: string[]): Verdict | null {
  if (gitGlobalIdentity(args)) return "GIT_IDENTITY";

  const rest = skipGitGlobals(args);
  if (rest.length === 0) return null;

  const sub = rest[0];
  const vo = valueOptsFor(sub);
  // "--" の後ろは全て pathspec/refspec なので、フラグの走査は区切りの手前だけを
  // 見る。"--force" という名前のパスをフラグと読まないためと、"--no-ext-diff" と
  // いう名前のパスで外部 diff のガードを外させないためである。
  const rules = gitOpts(rest.slice(1), vo.opts, vo.chars);

  if (
    sub === "push" &&
    rules.some(
      (a) =>
        a === "--force" ||
        (/^-[A-Za-z0-9]/.test(a) &&
          clusterFlags(a.slice(1), "o").includes("f")),
    )
  ) {
    return "FORCE_PUSH";
  }

  if (sub === "clean") {
    const letters = rules
      .filter((a) => /^-[A-Za-z0-9]/.test(a))
      .map((a) => clusterFlags(a.slice(1), "e"))
      .join("") + (rules.some((a) => isAbbrevOf(a, "--force", 3)) ? "f" : "");
    if (
      letters.includes("f") && (letters.includes("d") || letters.includes("x"))
    ) {
      return "GIT_CLEAN";
    }
  }

  if (
    sub === "reset" &&
    rules.includes("--hard") &&
    rules.some(
      (a) =>
        a.startsWith("origin/") ||
        a.startsWith("upstream/") ||
        a.startsWith("HEAD~") ||
        a.startsWith("HEAD@"),
    )
  ) {
    return "GIT_RESET_HARD";
  }

  if (
    (sub === "fetch" || sub === "pull") &&
    hasFlag(rules, [
      "--depth",
      "--shallow-since",
      "--shallow-exclude",
      "--update-shallow",
    ])
  ) {
    return "SHALLOW";
  }

  if (sub === "config" && configIdentityWrite(rest.slice(1))) {
    return "GIT_IDENTITY";
  }

  // --author が authorship を書き換えるのは、それを記録するコマンドだけ。
  // "git log --author" は絞り込みなので通す。
  if (
    (sub === "commit" || sub === "am") &&
    rules.some((a) => isAbbrevOf(a, "--author", 4))
  ) {
    return "GIT_IDENTITY";
  }

  // これらはコマンドを 1 つの文字列で受け取る。shfmt は 1 語として扱うので、
  // 下の identity 検査までは届かない。文字列の中の断片で見る。ここに identity の
  // キーを渡す正当な用途はない。
  if (
    (sub === "rebase" || sub === "filter-branch" || sub === "bisect") &&
    rules.some((a) =>
      a.includes("--author") || /user\.(email|name)/.test(a.toLowerCase())
    )
  ) {
    return "GIT_IDENTITY";
  }

  if (
    (sub === "diff" ||
      sub === "show" ||
      (sub === "log" &&
        rules.some(
          (a) =>
            a === "--patch" ||
            (/^-[A-Za-z0-9]/.test(a) &&
              /[pu]/.test(clusterFlags(a.slice(1), "GSOnL"))),
        ))) &&
    !rules.includes("--no-ext-diff")
  ) {
    return "EXTDIFF";
  }

  return null;
}

// --- コマンド単位の判定 ---------------------------------------------------

function commandVerdict(words: string[]): Verdict | null {
  const args = stripWrappers(words);
  if (args.length === 0) return null;

  const cmd = args[0];
  const rest = args.slice(1);

  if (cmd === "rm") return "RM";
  if (cmd === "eval") return "EVAL";
  if (cmd === "shred") return "SHRED";
  if (
    cmd === "pkill" &&
    optsBeforeDdash(rest).some((a) => a === "--full" || /^-[A-Za-z]*f/.test(a))
  ) {
    return "PKILL_F";
  }
  if (cmd === "killall") return "KILLALL";
  if (cmd.startsWith("mkfs.")) return "MKFS";
  if (cmd === "dd" && rest.some((a) => a.startsWith("of=/dev/"))) {
    return "DD_DEV";
  }

  if (cmd === "chmod") {
    // --reference では数値モードの引数が存在しない。"777" はファイル名
    // (参照元か対象パス) である。
    if (optsBeforeDdash(rest).some((a) => isAbbrevOf(a, "--reference", 5))) {
      return null;
    }
    if (!rest.some((a) => a === "777" || a === "0777")) return null;
    if (
      optsBeforeDdash(rest).some((a) =>
        /^-[a-zA-Z]*R/.test(a) || isAbbrevOf(a, "--recursive", 5)
      )
    ) {
      return "CHMOD_R_777";
    }
    if (rest.some((a) => a === "/")) return "CHMOD_777_ROOT";
    return null;
  }

  if (
    (cmd === "grep" || cmd === "egrep" || cmd === "fgrep") &&
    grepRecursive(rest)
  ) {
    return "GREP_R";
  }
  if (cmd === "git") return gitVerdict(rest);
  return null;
}

// --- AST 全体の走査 -------------------------------------------------------

const GIT_IDENTITY_VAR = /^GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)$/;
const GIT_IDENTITY_ASSIGN = /^GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)=/;

// 判定を出る順に返す。採用するのは先頭 1 つだけだが、順序は
// scripts/verdict-precedence-cases.txt が固定している契約なので、
// 途中で打ち切らずに並びとして組み立てる。
export function analyze(ast: unknown): Verdict[] {
  const nodes = [...walk(ast)];
  const callExprWords = nodes
    .filter((node) => node.Type === "CallExpr")
    .map((node) => (Array.isArray(node.Args) ? node.Args.map(wordText) : []));

  const verdicts: Verdict[] = [];

  // GIT_AUTHOR_* / GIT_COMMITTER_* は config を触らずに identity を変える。
  // 代入の前置でも export でも AST では Assign ノードになる。Assign は Type を
  // 持たないので、変数名の形で見分ける。
  for (const node of nodes) {
    const name = isNode(node.Name) ? node.Name.Value : undefined;
    if (typeof name === "string" && GIT_IDENTITY_VAR.test(name)) {
      verdicts.push("GIT_IDENTITY");
    }
  }

  // env 経由なら素の語として届く。
  for (const words of callExprWords) {
    for (const word of words) {
      if (GIT_IDENTITY_ASSIGN.test(word)) verdicts.push("GIT_IDENTITY");
    }
  }

  for (const words of callExprWords) {
    const verdict = commandVerdict(words);
    if (verdict !== null) verdicts.push(verdict);
  }

  return verdicts;
}

// --- テキストパターン -----------------------------------------------------

interface Rule {
  pattern: string;
  message: string;
}

export function matchTextRule(command: string, rules: Rule[]): string | null {
  for (const rule of rules) {
    if (new RegExp(toEcmaScript(rule.pattern)).test(command)) {
      return rule.message;
    }
  }
  return null;
}

// --- 入口 -----------------------------------------------------------------

const RULES_PATH = new URL("./banned-commands.json", import.meta.url);

function block(message: string): never {
  console.error(message);
  Deno.exit(2);
}

async function main(): Promise<void> {
  const shfmt = Deno.args[0] || "shfmt";

  const payload = JSON.parse(await new Response(Deno.stdin.readable).text());
  const command = payload?.tool_input?.command;
  if (typeof command !== "string") {
    block(
      "banned-commands hook received no tool_input.command string; refusing to run the command unchecked.",
    );
  }

  const message = matchTextRule(
    command,
    JSON.parse(Deno.readTextFileSync(RULES_PATH)) as Rule[],
  );
  if (message !== null) block(message);

  // shfmt は stdin だけで動くので環境変数を渡さない。渡すと Deno が
  // LD_LIBRARY_PATH の継承に --allow-env まで要求する。
  const shfmtRun = new Deno.Command(shfmt, {
    args: ["--tojson"],
    clearEnv: true,
    stdin: "piped",
    stdout: "piped",
    stderr: "null",
  }).spawn();
  const writer = shfmtRun.stdin.getWriter();
  await writer.write(new TextEncoder().encode(command + "\n"));
  await writer.close();
  const { code, stdout } = await shfmtRun.output();
  if (code !== 0) {
    block(
      "banned-commands hook could not parse this command as bash (syntax error, or shfmt unavailable); refusing to run it unchecked. Fix the command and retry.",
    );
  }

  let ast: unknown;
  try {
    ast = JSON.parse(new TextDecoder().decode(stdout));
  } catch {
    block(
      "banned-commands hook could not parse this command as bash (syntax error, or shfmt unavailable); refusing to run it unchecked. Fix the command and retry.",
    );
  }

  const verdict = analyze(ast)[0];
  if (verdict === undefined) return;

  const text = VERDICT_MESSAGES[verdict];
  block(
    text ??
      "banned-commands hook produced an unknown verdict; refusing to run the command unchecked.",
  );
}

if (import.meta.main) {
  // Anything main() did not anticipate — malformed payload JSON, an unreadable
  // rules file, a pattern that will not compile, shfmt failing to spawn — must
  // still block. An uncaught throw exits 1, which Claude Code lets through.
  try {
    await main();
  } catch (error) {
    block(
      `banned-commands hook failed before reaching a verdict (${
        error instanceof Error ? error.message : String(error)
      }); refusing to run the command unchecked.`,
    );
  }
}
