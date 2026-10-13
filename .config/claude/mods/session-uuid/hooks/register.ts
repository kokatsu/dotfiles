import type { Register } from "claude-code";

export const register: Register = (on) => {
  // /clear reloads no module (no session.start fires for it), so the ending
  // session's id waits here for the fresh session's SessionStart.
  let previous: string | undefined;

  on("session.end", (_$, e, next) => {
    if (e.reason === "clear") previous = e.sessionId;
    return next(e);
  });

  on("classic.SessionStart", { source: "clear" }, async ($, e, next) => {
    const result = await next(e);
    if (!e.agent_id && previous) {
      $.ui.log(`Previous session UUID: ${previous}`);
      previous = undefined;
    }
    return result;
  });
};
