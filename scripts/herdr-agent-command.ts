#!/usr/bin/env -S deno run --no-config --no-lock --allow-env --allow-read --allow-write --allow-run --allow-sys=uid

const commands = new Set(["/clear", "/copy", "/exit"]);
type Env = Record<string, string | undefined>;
type Run = (args: string[], timeout?: number) => Promise<string>;
export type Prompt = {
  kind: "empty" | "draft" | "blank" | "unknown";
  text: string;
};
type Cell = { char: string; dim: boolean };
const unknown: Prompt = { kind: "unknown", text: "" };

export class CommandError extends Error {}

function terminalLines(ansi: string): Cell[][] | null {
  const lines: Cell[][] = [[]];
  let dim = false;
  let offset = 0;
  for (
    const token of ansi.matchAll(
      // deno-lint-ignore no-control-regex -- Terminal snapshots contain ANSI controls.
      /\x1b\[([0-9;]*)m|\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)|([^\x1b]+)/gs,
    )
  ) {
    if (token.index !== offset) return null;
    offset += token[0].length;
    if (token[1] !== undefined) {
      const codes = (token[1] || "0").split(";").map(Number);
      for (let i = 0; i < codes.length; i++) {
        const code = codes[i];
        if (code === 0 || code === 22) dim = false;
        else if (code === 2) dim = true;
        else if ([38, 48, 58].includes(code)) {
          // RGB's color-mode value 2 is not the SGR faint attribute.
          const mode = codes[++i];
          const count = mode === 2 ? 3 : mode === 5 ? 1 : 0;
          if (!count || i + count >= codes.length) return null;
          for (let n = 0; n < count; n++) {
            const value = codes[++i];
            if (value < 0 || value > 255) return null;
          }
        } else if (
          ![1, 3, 4, 5, 6, 7, 9, 21, 23, 24, 25, 27, 28, 29, 39, 49, 53, 55, 59]
            .includes(code) &&
          !(code >= 30 && code <= 37) && !(code >= 40 && code <= 47) &&
          !(code >= 90 && code <= 97) && !(code >= 100 && code <= 107)
        ) return null;
      }
    } else if (token[2] !== undefined) {
      for (const char of token[2].replaceAll("\r\n", "\n")) {
        if (char === "\n") lines.push([]);
        else if (char.codePointAt(0)! < 32 || char === "\x7f") return null;
        else lines.at(-1)!.push({ char, dim });
      }
    }
  }
  return offset === ansi.length ? lines : null;
}

function codexPrompt(lines: Cell[][], submittedCommand?: string): Prompt {
  const text = lines.map((line) => line.map((cell) => cell.char).join(""));
  const footer = text.findLastIndex((line) => /^ {2}GPT-/.test(line));
  const top = text.slice(0, footer).findLastIndex((line) => /^› /.test(line));
  const below = text.slice(footer + 1).filter((line) => line.trim());
  if (
    top < 1 || footer - top < 2 || text[top - 1].trim() ||
    text[footer - 1].trim() ||
    below.length > 1 ||
    below.some((line) =>
      !/^ {2}(?:← for agents · )?\? for shortcuts$/.test(line.trimEnd())
    )
  ) return unknown;
  const region = text.slice(Math.max(0, top - 2)).join("\n");
  if (
    /\b(?:NORMAL|INSERT|REPLACE)\b|\[(?:Pasted|Image|File|Attachment)\b/i.test(
      region,
    )
  ) {
    return unknown;
  }
  const rows = lines.slice(top, footer - 1);
  if (text.slice(top + 1, footer - 1).some((line) => !line.startsWith("  "))) {
    return unknown;
  }
  // The captured terminal pads rows with spaces; a filled row may be wrapped.
  const width = lines[top - 1].length;
  if (width > 8 && rows.some((row) => row.at(-1)?.char !== " ")) return unknown;
  const input = rows.map((row) => {
    const cells = row.slice(2);
    while (cells.at(-1)?.char === " ") cells.pop();
    return cells;
  });
  const value = input.map((row) => row.map((cell) => cell.char).join(""))
    .join("\n");
  const selected = text[top - 2]?.match(/^›\s+(\/\S+)\s+/)?.[1];
  if (
    selected &&
    (!submittedCommand || selected !== value || value !== submittedCommand)
  ) {
    return unknown;
  }
  if (!value.replaceAll("\n", "")) {
    return rows.length === 1 ? { kind: "blank", text: "" } : unknown;
  }
  const cells = input.flat();
  if (cells.some((cell) => cell.dim)) {
    return rows.length === 1 && value === "Ask Codex to do anything" &&
        cells.every((cell) => cell.dim)
      ? { kind: "empty", text: "" }
      : unknown;
  }
  if (value.trimStart().startsWith("!") || /^[\s]*$/.test(value)) {
    return unknown;
  }
  return { kind: "draft", text: value };
}

export function readPrompt(
  ansi: string,
  submittedCommand?: string,
  agent = "claude",
): Prompt {
  if (!ansi.includes("\x1b[")) return unknown;
  const lines = terminalLines(ansi);
  if (!lines) return unknown;
  if (agent === "codex") return codexPrompt(lines, submittedCommand);
  if (agent !== "claude") return unknown;
  const text = lines.map((line) => line.map((cell) => cell.char).join(""));
  if (/\[(?:Image|File|Attachment)\b/i.test(text.join("\n"))) return unknown;
  const border = (line: string) => /^\s*─{8,}\s*$/.test(line);
  const bottom = text.findLastIndex(border);
  const top = text.slice(0, bottom).findLastIndex(border);
  if (top < 0 || bottom <= top + 1) return unknown;
  if (!/^❯[ \u00a0]/.test(text[top + 1])) return unknown;
  const region = text.slice(top + 1).join("\n");
  if (/\b(?:NORMAL|INSERT|REPLACE)\b/.test(region)) return unknown;
  const input = [lines[top + 1].slice(2), ...lines.slice(top + 2, bottom)];
  const value = input.map((line) => line.map((cell) => cell.char).join(""))
    .join("\n");
  const footer = text.slice(bottom + 1).join("\n");
  const selected = footer.match(/^\s*❯\s+(\S+)/m)?.[1];
  if (selected) {
    if (!submittedCommand || value !== submittedCommand || selected !== value) {
      return unknown;
    }
  } else if (!footer.includes("🤖")) return unknown;
  if (value.trimStart().startsWith("!")) return unknown;
  if (/\[(?:Pasted|Image|File|Attachment)\b/i.test(value)) return unknown;
  if (/^[ \u00a0\u3000\n]*$/.test(value)) {
    return input.length === 1 ? { kind: "blank", text: value } : unknown;
  }
  const cells = input.flat();
  if (
    /^Try "/.test(value) && cells.some((cell) => cell.dim) &&
    !cells.every((cell) => cell.dim)
  ) return unknown;
  if (cells.every((cell) => cell.dim)) {
    return input.length === 1 && /^Try "[^"\r\n]+"$/.test(value)
      ? { kind: "empty", text: "" }
      : unknown;
  }
  return { kind: "draft", text: value };
}

export function transport(env: Env): Run {
  return async (args, remaining = 3000) => {
    const child = new Deno.Command(env.HERDR_BIN_PATH || "herdr", {
      args,
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    const timer = setTimeout(() => {
      try {
        child.kill("SIGKILL");
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
    }, Math.min(3000, remaining));
    try {
      const result = await child.output();
      if (!result.success) throw new CommandError("Herdr の操作に失敗しました");
      return new TextDecoder().decode(result.stdout);
    } finally {
      clearTimeout(timer);
    }
  };
}

export class AgentCommands {
  constructor(
    private env: Env,
    private run: Run = transport(env),
    private timeout = 8000,
  ) {}

  private async directory(pane: string): Promise<string> {
    if (!/^[A-Za-z0-9:_-]+$/.test(pane)) {
      throw new CommandError("ペイン ID が不正です");
    }
    const base = Deno.build.os === "darwin"
      ? this.env.TMPDIR
      : this.env.XDG_RUNTIME_DIR;
    if (!base?.startsWith("/")) {
      throw new CommandError("ユーザーの一時ディレクトリを確認できません");
    }
    const hash = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(this.env.HERDR_SOCKET_PATH || "default"),
    );
    const scope = Array.from(new Uint8Array(hash).slice(0, 8))
      .map((value) => value.toString(16).padStart(2, "0")).join("");
    let path = base.replace(/\/$/, "");
    for (const part of ["herdr-agent-command", scope, pane]) {
      path += `/${part}`;
      try {
        await Deno.mkdir(path, { mode: 0o700 });
      } catch (error) {
        if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
      }
      const stat = await Deno.lstat(path);
      if (
        !stat.isDirectory || stat.uid !== Deno.uid() || (stat.mode! & 0o077)
      ) {
        throw new CommandError("一時ディレクトリの所有者または権限が不正です");
      }
    }
    return path;
  }

  async send(command: string): Promise<void> {
    if (!commands.has(command)) {
      throw new CommandError("対応していないコマンドです");
    }
    const deadline = performance.now() + this.timeout;
    const run: Run = async (args) => {
      const remaining = deadline - performance.now();
      if (remaining <= 0) {
        throw new CommandError("コマンド送信がタイムアウトしました");
      }
      const result = await this.run(args, Math.min(3000, remaining));
      if (performance.now() >= deadline) {
        throw new CommandError("コマンド送信がタイムアウトしました");
      }
      return result;
    };
    const pane = this.env.HERDR_ACTIVE_PANE_ID || "";
    const directory = await this.directory(pane);
    // Unlinking the lock file would let another sender lock a different inode.
    using lock = await Deno.open(`${directory}/lock`, {
      create: true,
      write: true,
      mode: 0o600,
    });
    if (!lock.tryLockSync(true)) {
      throw new CommandError("同じペインへのコマンド送信中です");
    }
    const state = async (allowWorking = false) => {
      const current = JSON.parse(await run(["pane", "get", pane])).result.pane;
      if (
        !["claude", "codex"].includes(current.agent) ||
        (current.agent === "claude" &&
          (typeof current.agent_session?.value !== "string" ||
            !current.agent_session.value))
      ) {
        throw new CommandError(
          "対応するエージェントのセッションを確認できません",
        );
      }
      const ready = ["idle", "done"].includes(current.agent_status);
      if (!ready && !(allowWorking && current.agent_status === "working")) {
        throw new CommandError("エージェントが入力待ちではありません");
      }
      return {
        agent: current.agent as string,
        session: current.agent_session?.value as string | undefined,
        ready,
      };
    };
    // Herdr reports a freshly started agent as unknown for a few seconds.
    const startup = async () => {
      while (true) {
        const current = JSON.parse(await run(["pane", "get", pane])).result
          .pane;
        if (
          !["claude", "codex"].includes(current.agent) ||
          current.agent_status !== "unknown"
        ) return state();
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
    };
    const { agent, session } = await startup();
    let shellPid: number | undefined;
    let codexPid: number | undefined;
    const processInfo = async () =>
      JSON.parse(await run(["pane", "process-info", "--pane", pane])).result
        .process_info;
    const foreground = async () => {
      const info = await processInfo();
      if (
        shellPid === undefined && Number.isInteger(info.shell_pid) &&
        info.shell_pid > 0
      ) {
        shellPid = info.shell_pid;
      }
      const foreground: { name: string; pid: number }[] =
        info.foreground_processes || [];
      const codex = foreground.filter((p) => p.name === "codex");
      if (agent === "codex") {
        if (
          codex.length !== 1 || !Number.isInteger(codex[0].pid) ||
          codex[0].pid <= 0 ||
          (codexPid !== undefined && codex[0].pid !== codexPid)
        ) {
          throw new CommandError("前景の Codex プロセスが変わりました");
        }
        codexPid = codex[0].pid;
      } else if (
        !foreground.length || !foreground.every((p) => p.name === "claude")
      ) {
        throw new CommandError("前景のエージェントが変わりました");
      }
    };
    const same = async () => {
      const current = await state();
      if (
        current.agent !== agent ||
        (agent === "claude" && current.session !== session)
      ) {
        throw new CommandError("エージェントのセッションが変わりました");
      }
      await foreground();
    };
    const read = async (submitted?: string) =>
      readPrompt(
        await run([
          "pane",
          "read",
          pane,
          "--source",
          "visible",
          "--lines",
          "80",
          "--ansi",
        ]),
        submitted,
        agent,
      );
    const prompt = async (submitted?: string) => {
      await same();
      return read(submitted);
    };
    const wait = async (
      accept: (value: Prompt) => boolean,
      submitted?: string,
    ) => {
      while (true) {
        const current = await prompt(submitted);
        if (accept(current)) return;
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
    };
    const initial = await prompt();
    const empty = (value: Prompt) =>
      value.kind === "empty" ||
      (agent === "claude" && value.kind === "blank");
    if (initial.kind === "unknown") {
      throw new CommandError("通常の入力欄を確認できません");
    }
    if (command === "/exit" && shellPid === undefined) {
      throw new CommandError("終了後に戻るシェルを確認できません");
    }
    const cleared = initial.kind !== "empty";
    if (cleared) {
      const latest = await prompt();
      if (latest.kind !== initial.kind) {
        throw new CommandError("消去前に入力欄の状態が変わりました");
      }
      await same();
      await run([
        "agent",
        "send-keys",
        pane,
        ...(initial.kind === "blank"
          ? ["ctrl+e", "ctrl+u"]
          : agent === "codex"
          ? ["ctrl+c"]
          : ["esc", "esc"]),
      ]);
      await wait(empty);
    }
    const beforeInput = await prompt();
    if (
      beforeInput.kind !== "empty" &&
      !(agent === "claude" && cleared && beforeInput.kind === "blank")
    ) throw new CommandError("空の入力欄を確認できません");
    await same();
    await run(["pane", "send-text", pane, command]);
    await wait(
      (value) => value.kind === "draft" && value.text === command,
      command,
    );
    await same();
    const beforeEnter = await prompt(command);
    if (beforeEnter.kind !== "draft" || beforeEnter.text !== command) {
      throw new CommandError("指定コマンドだけの入力欄を確認できません");
    }
    await same();
    try {
      await run(["agent", "send-keys", pane, "enter"]);
    } catch {
      throw new CommandError(
        "Enter の送信結果は不明です。実行済みの可能性があります",
      );
    }
    try {
      // Herdr acknowledges delivery before the CLI has processed Enter.
      while (true) {
        if (command === "/exit") {
          const info = await processInfo();
          const foreground: { name: string; pid: number }[] =
            info.foreground_processes || [];
          // zeno.zsh's deno server stays in the shell's foreground group.
          if (
            info.shell_pid === shellPid &&
            foreground.some((p) => p.pid === shellPid) &&
            !foreground.some((p) => p.name === agent)
          ) return;
        } else if (command === "/clear") {
          // Claude's /clear runs SessionEnd hooks before the next idle session.
          const current = await state(true);
          await foreground();
          if (current.agent !== agent) {
            throw new CommandError("対象が変わりました");
          }
          if (
            current.ready && (agent === "codex" || current.session !== session)
          ) {
            const view = await read();
            const confirmed = await state(true);
            if (
              confirmed.agent === agent && confirmed.ready &&
              (agent === "codex" || confirmed.session === current.session) &&
              empty(view)
            ) return;
          }
        } else {
          const current = await prompt();
          if (empty(current)) return;
        }
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
    } catch {
      throw new CommandError(
        "Enter 後の入力待ちへの復帰を確認できません。実行済みの可能性があります",
      );
    }
  }
}

export async function main(
  args: string[],
  env: Env,
  run: Run = transport(env),
) {
  try {
    if (args.length !== 1) throw new CommandError("引数が不正です");
    await new AgentCommands(env, run).send(args[0]);
    return 0;
  } catch (error) {
    const message = error instanceof CommandError
      ? error.message
      : "コマンド送信の処理に失敗しました";
    console.error(message);
    try {
      await run([
        "notification",
        "show",
        "コマンドの送信を確認できませんでした",
        "--body",
        `${message}。入力欄を確認してください。自動再送はしません`,
        "--sound",
        "none",
      ]);
    } catch { /* The original error is already on stderr. */ }
    return 1;
  }
}

if (import.meta.main) Deno.exit(await main(Deno.args, Deno.env.toObject()));
