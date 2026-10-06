import { expect, test } from "claude-code/testing";
import {
  buildEvidence,
  EARLIER_CHARS,
  latestTurnStart,
  type Message,
} from "./evidence.ts";

const reminder = (text: string) => ({
  type: "text",
  text: `<system-reminder>\n${text}\n</system-reminder>`,
});
const prompt = (text: string, ...context: string[]): Message => ({
  role: "user",
  content: [...context.map(reminder), { type: "text", text }],
});
let nextId = 0;
const bash = (output: unknown): Message[] => {
  const id = `t${nextId++}`;
  return [
    {
      role: "assistant",
      content: [
        { type: "thinking", thinking: "SECRET-THOUGHT" },
        { type: "tool_use", id, name: "Bash", input: { command: "cat x" } },
      ],
    },
    {
      role: "user",
      content: [{ type: "tool_result", tool_use_id: id, content: output }],
    },
  ];
};
const say = (text: string): Message => ({
  role: "assistant",
  content: [{ type: "text", text }],
});
const stopFeedback: Message = {
  role: "user",
  content: [{ type: "text", text: "Stop hook feedback:\nUnsupported: x" }],
};
const reminderOnly: Message = {
  role: "user",
  content: [reminder("The user hasn't heard from you")],
};

test("the latest turn starts at the last typed prompt", () => {
  const msgs = [
    prompt("first"),
    ...bash("a"),
    say("ok"),
    prompt("second"),
    ...bash("b"),
    say("done"),
    stopFeedback,
    reminderOnly,
  ];
  expect(latestTurnStart(msgs)).toBe(4);
});

test("earlier tool output is truncated, context and the latest turn are whole", () => {
  const long = "x".repeat(EARLIER_CHARS + 500);
  const memory = `MEMORY ${"m".repeat(EARLIER_CHARS + 500)}`;
  const { text, latestChars } = buildEvidence([
    prompt("first", memory),
    ...bash(long),
    say("ok"),
    prompt("second"),
    ...bash(long),
  ]);
  const [earlier, latest] = text.split("## Latest turn");
  expect(earlier).toContain("500 more chars truncated");
  expect(earlier).toContain(`[context]\n<system-reminder>\n${memory}`);
  expect(latest).toContain(long);
  expect(latest).not.toContain("truncated");
  expect(latestChars).toBeGreaterThan(long.length);
});

test("array tool results are rendered and paired with their call", () => {
  const { text } = buildEvidence([
    prompt("q"),
    ...bash([{ type: "text", text: "LINE-ONE" }, { type: "image" }]),
  ]);
  expect(text).toContain('[tool Bash]\ninput: {"command":"cat x"}');
  expect(text).toContain("LINE-ONE\n[image]");
});

test("assistant prose and thinking are never evidence", () => {
  const { text } = buildEvidence([
    prompt("q"),
    ...bash("a"),
    say("THE-ANSWER-SAYS-SO"),
  ]);
  expect(text).not.toContain("THE-ANSWER-SAYS-SO");
  expect(text).not.toContain("SECRET-THOUGHT");
});

test("Stop hook feedback is context, not the start of a turn", () => {
  const msgs = [prompt("q"), ...bash("a"), say("done"), stopFeedback];
  expect(latestTurnStart(msgs)).toBe(0);
  expect(buildEvidence(msgs).text).toContain(
    "[context]\nStop hook feedback:\nUnsupported: x",
  );
});
