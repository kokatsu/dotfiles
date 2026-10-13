import { expect, test } from "claude-code/testing";

const before = "00000000-0000-0000-0000-000000000001";
const after = "00000000-0000-0000-0000-000000000002";

test("clear logs the UUID of the session it ended", async ($, on) => {
  const calls: string[] = [];
  on("session.end", (_$, e) => ({ sessionId: e.sessionId }));
  on("classic.SessionStart", () => {
    calls.push("existing hooks");
    return { additionalContext: ["existing context"] };
  });
  on("ui.log", (_$, e, next) => {
    calls.push(e.text);
    expect(e.to).toBe("transcript");
    return next(e);
  });
  await $.session.end({
    reason: "clear",
    sessionId: before,
    resume: { id: before },
  });
  const result = await $.classic.SessionStart({
    source: "clear",
    session_id: after,
  });
  expect(calls).toEqual(["existing hooks", `Previous session UUID: ${before}`]);
  expect(result.additionalContext).toEqual(["existing context"]);
});

test("other endings, other starts and subagents stay quiet", async ($, on) => {
  const logs: string[] = [];
  on("session.end", (_$, e) => ({ sessionId: e.sessionId }));
  on("classic.SessionStart", () => ({}));
  on("ui.log", (_$, e, next) => {
    logs.push(e.text);
    return next(e);
  });
  await $.session.end({
    reason: "resume",
    sessionId: before,
    resume: { id: before },
  });
  await $.classic.SessionStart({ source: "clear", session_id: after });
  await $.session.end({
    reason: "clear",
    sessionId: before,
    resume: { id: before },
  });
  for (const source of ["startup", "resume", "compact", "fork"] as const) {
    await $.classic.SessionStart({ source, session_id: after });
  }
  await $.classic.SessionStart({
    source: "clear",
    session_id: "sub",
    agent_id: "a1",
  });
  expect(logs).toEqual([]);
});
