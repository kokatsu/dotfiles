import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

// "@earendil-works/pi-coding-agent" resolves only inside Pi, so `deno check`
// sees this subset of its ExtensionAPI instead.
type ToolCallEvent = { toolName: string; input: Record<string, unknown> };
type ToolCallResult = { block: true; reason: string } | undefined;
type ExtensionAPI = {
  on(
    event: "tool_call",
    handler: (
      event: ToolCallEvent,
      ctx: { cwd: string },
    ) => Promise<ToolCallResult>,
  ): void;
};

// Pi has no approval prompt or sandbox, so agent-guard is the only check before
// a tool runs. Its modes take Claude Code's PreToolUse payload.
function runGuard(
  mode: string,
  payload: unknown,
  cwd: string,
): Promise<string | undefined> {
  return new Promise((resolve) => {
    const child = spawn("agent-guard", [mode], {
      cwd,
      stdio: ["pipe", "ignore", "pipe"],
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.stdin.on("error", () => {});
    child.on(
      "error",
      (err) =>
        resolve(
          `agent-guard not found; run home-manager switch (${err.message})`,
        ),
    );
    // Exit 2 is a block; any other failure did not reach a verdict, so it blocks too.
    child.on(
      "close",
      (code) =>
        resolve(
          code === 0
            ? undefined
            : stderr.trim() || `agent-guard ${mode} exited with ${code}`,
        ),
    );
    child.stdin.end(JSON.stringify(payload));
  });
}

// Mirrors resolvePath in Pi's dist/utils/paths.js (POSIX branch), which edit
// and write use. Any input it maps differently would let a write skip the guard.
export function targetPath(input: string, cwd: string): string {
  let p = input.replace(/[  -   　]/g, " ");
  if (p.startsWith("@")) p = p.slice(1);
  if (p === "~") p = os.homedir();
  else if (p.startsWith("~/")) p = path.join(os.homedir(), p.slice(2));
  else if (p.startsWith("file://")) p = fileURLToPath(p);
  return path.resolve(cwd, p);
}

// Tools that only read, plus subagent, whose child `pi` loads this extension
// and checks its own tool calls. Any other tool, such as powershell or one a
// project enables with a `+name` defaultTools entry, may run commands this
// guard never sees.
const passThroughTools = new Set(["read", "grep", "find", "ls", "subagent"]);

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (passThroughTools.has(event.toolName)) return undefined;
    let reason: string | undefined;
    if (event.toolName === "bash") {
      reason = await runGuard("pi", {
        tool_name: "Bash",
        tool_input: { command: event.input.command },
      }, ctx.cwd);
    } else if (event.toolName === "edit" || event.toolName === "write") {
      const filePath = typeof event.input.path === "string"
        ? targetPath(event.input.path, ctx.cwd)
        : undefined;
      reason = await runGuard("managed-paths", {
        tool_name: "Write",
        tool_input: { file_path: filePath },
      }, ctx.cwd);
    } else {
      reason =
        `agent-guard has no check for the ${event.toolName} tool; run it yourself if intended`;
    }
    return reason === undefined ? undefined : { block: true, reason };
  });
}
