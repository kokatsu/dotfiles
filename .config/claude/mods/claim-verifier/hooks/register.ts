import type { EngineInterface, Register } from "claude-code";
import { lineAppender } from "./append.ts";
import { buildEvidence } from "./evidence.ts";

const appendLine = lineAppender();

const SYSTEM =
  `You audit one assistant response for unsupported factual claims. The user message holds the evidence and then the response to judge. In the evidence, [user] is what the person typed, [tool ...] is a tool call with its output, and [context] is text the harness injected (environment, hook output, skill bodies, memory, instruction files).

Flag a sentence only if it asserts a fact about code, files, specs, external services or tools, or the assistant's own past actions, and nothing in the evidence supports it. Support is [user] text, tool outputs, and [context] text that reports something checked or produced in this session (environment facts, hook output, skill bodies). Memory files (MEMORY.md and the memory notes it indexes) and instruction files (CLAUDE.md, AGENTS.md, rules) are context only: they tell you what the assistant was told, not what is true now, so a factual claim resting only on them is unsupported. This includes negative and capability claims (that something does not exist, cannot be done, or is not visible to the assistant) and claims about how Claude Code, its hooks and tools, or the assistant's own context work. An explanation or reason given in the response is not support. A search with zero results does not support a claim that something does not exist. Earlier tool outputs are truncated: if a claim concerns the subject of an earlier tool call and its support could lie in the truncated part, do not flag it.

Also flag a sentence that leaves a question open (labels it unverified, inferred, unknown or not yet checked, e.g. 推定, 未確認, 確かめていない, 分からない) or hands it to the person or a later step to check, when the assistant could have settled it with its own tools: either the question is about the code being worked on and is the kind reading its code or config settles (what a function reads or writes, which inputs a feature accepts, whether a branch exists, where a value comes from), or the evidence names a local file of the same repository that likely answers it (notes or records from earlier work, a local copy of docs). For this rule, a record named in [context] or in any tool output counts as reason to flag, even though it is not support under the first rule. Do not flag under this rule a question that reading cannot settle, such as how a running system behaves or what live data holds; a repository or document the assistant can read with its tools, public or one the user has access to, including the published source of a tool or library the response names, does not count as unavailable; a sentence that separates what was checked from what was not is exempt only when the unchecked part is of that kind. For each sentence flagged under this rule, say what to read or search instead of what is missing.

Do not flag, except under the rule above: a claim whose own sentence labels it as unverified, inferred, or a guess in any language (e.g. 未確認, 未検証, 推定); a sentence that explicitly says it covers everything that follows, or names the sentences it covers (e.g. 以下はすべて未検証), exempts those sentences, but a heading alone or a label on an unrelated sentence does not; opinions, recommendations, and plans; restatements of what the user said; small talk.

Your own knowledge is not support, even when you believe the claim is true; judge only by the evidence. Judge only evidential support; never request any other work. Reply with JSON only: {"ok": true} when nothing is flagged, otherwise {"ok": false, "reason": "<every flagged sentence, quoted, each followed by what is missing>"}, the reason written in the language of the response.`;

type Verdict = { ok: boolean; reason?: string };

function parseVerdict(text: string): Verdict | undefined {
  const json = text.match(/\{[\s\S]*\}/)?.[0];
  if (json === undefined) return undefined;
  try {
    const v = JSON.parse(json) as Verdict;
    return typeof v.ok === "boolean" ? v : undefined;
  } catch {
    return undefined;
  }
}

async function logPath($: EngineInterface, sessionId: string): Promise<string> {
  return `${await $.env.get(
    "HOME",
  )}/.local/state/claim-verifier/${sessionId}.jsonl`;
}

async function judge(
  $: EngineInterface,
  sessionId: string,
  prompt: string,
  evidenceChars: number,
  latestChars: number,
): Promise<Verdict | undefined> {
  const started = Date.now();
  const judged = await $.model.complete({
    model: "sonnet",
    system: SYSTEM,
    prompt,
    maxTokens: 4096,
    effort: "high",
    timeoutMs: 110_000,
  });
  const mineMs = Date.now() - started;
  const verdict = judged.isAnswered ? parseVerdict(judged.text) : undefined;
  if (verdict?.ok === false) {
    // A log row is one line: a newline inside it is drawn as U+FFFD.
    const lines = (verdict.reason ?? "").split("\n").filter((line) =>
      line.trim() !== ""
    );
    for (const line of ["根拠を確認できなかった文:", ...lines]) $.ui.log(line);
  }

  const path = await logPath($, sessionId);
  const entry = {
    at: new Date().toISOString(),
    evidenceChars,
    latestChars,
    mineMs,
    usage: judged.usage,
    mine: verdict ??
      {
        error: judged.isAnswered
          ? `unparsable: ${judged.text.slice(0, 200)}`
          : judged.reason,
      },
  };
  await appendLine(
    {
      exists: (p) => $.fs.exists(p),
      read: (p) => $.fs.read(p),
      write: (p, text) => $.fs.write(p, text),
    },
    path,
    JSON.stringify(entry),
  );
  return verdict;
}

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    await $.command.register({
      name: "claim",
      description: "Put a claim-verifier flag into the prompt box to send",
      argumentHint: "[n: 1 is the latest flag]",
      immediate: true,
    });
    return next(e);
  });

  // The flag goes into the prompt box, never into the command's output, which
  // the model would read: the person decides what, if anything, is sent.
  on("command.run", { command: "claim" }, async ($, e) => {
    const n = e.args.trim() === "" ? 1 : Number(e.args.trim());
    const path = await logPath($, await $.session.id());
    const log = (await $.fs.exists(path)) ? await $.fs.read(path) : "";
    const flags = log.split("\n").filter((line) => line !== "")
      .map((line) => JSON.parse(line) as { mine?: Verdict })
      .flatMap((entry) => entry.mine?.ok === false ? [entry.mine] : []);
    const flag = Number.isInteger(n) && n >= 1 ? flags.at(-n) : undefined;
    if (flag === undefined) {
      $.ui.toast(
        `claim-verifier: no flag #${
          e.args.trim() || 1
        } (${flags.length} in this session)`,
      );
      return {};
    }
    const filled = await $.prompt.fill({
      text:
        `claim-verifier が根拠を確認できなかった文です。確認してください。\n${
          flag.reason ?? ""
        }`,
      mode: "insert",
    });
    if (!filled.isFilled) {
      $.ui.toast(
        `claim-verifier: the prompt box did not take the flag (${
          filled.refusal ?? "refused"
        })`,
      );
    }
    return {};
  });

  on("classic.Stop", async ($, e, next) => {
    const messages = await $.session.messages({ as: "api" });
    const answer = e.last_assistant_message ??
      messages.findLast((m) => m.role === "assistant")?.content
        .flatMap((b) => b.type === "text" ? [String(b.text)] : []).join("\n") ??
      "";
    const { text: evidence, latestChars } = buildEvidence(messages);
    const prompt = [evidence, "## Response to judge", answer].join("\n\n");

    let verdict: Verdict | undefined;
    try {
      verdict = await judge(
        $,
        e.session_id,
        prompt,
        evidence.length,
        latestChars,
      );
    } catch (error: unknown) {
      $.ui.log(`claim-verifier: ${String(error)}`, { to: "debug" });
    }
    const result = await next(e);
    // One send-back per turn: the rewrite is judged and logged, never blocked,
    // so a judge that keeps flagging cannot hold the turn open.
    if (verdict?.ok !== false || e.stop_hook_active) return result;
    return {
      ...result,
      block:
        `根拠を確認できなかった文、または手元で確かめられるのに未確認とした文があります。ツールで確認してから、直前の回答全体を書き直してください。ツールで読める情報では確かめようがない文に限り、未検証と明記してかまいません。読み手はこの書き直しだけを読むので、指摘への返答ではなく、元の回答に代わる完全な回答にしてください。\n${
          verdict.reason ?? ""
        }`,
    };
  }).catch((_$, e, next) => next(e));
};
