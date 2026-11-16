import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { targetPath } from "./agent-guard.ts";

type TextContent = { type: "text"; text: string };
type ToolResultEvent = {
  toolName: string;
  input: Record<string, unknown>;
  content: unknown[];
  isError: boolean;
};
type ExtensionAPI = {
  on(
    event: "tool_result",
    handler: (
      event: ToolResultEvent,
      ctx: { cwd: string; signal?: AbortSignal },
    ) => Promise<{ content: unknown[] } | undefined>,
  ): void;
};

// The script takes Claude Code's PostToolUse payload and always exits 0: a
// finding comes back as `reason`, a check that could not run as `systemMessage`.
function runCheck(
  payload: unknown,
  cwd: string,
  signal: AbortSignal | undefined,
): Promise<string> {
  const script = path.join(
    process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"),
    "ai-writing/check-ai-writing.sh",
  );
  return new Promise((resolve) => {
    const child = spawn("bash", [script], {
      cwd,
      signal,
      timeout: 15_000,
      stdio: ["pipe", "pipe", "ignore"],
    });
    let stdout = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stdin.on("error", () => {});
    child.on(
      "error",
      (err) => resolve(`AI 文体検査を起動できませんでした: ${err.message}`),
    );
    child.on("close", () => resolve(stdout.trim()));
    child.stdin.end(JSON.stringify(payload));
  });
}

function reportText(output: string): string {
  try {
    const parsed = JSON.parse(output);
    return parsed.reason ?? parsed.systemMessage ?? output;
  } catch {
    return output;
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "edit" && event.toolName !== "write") {
      return undefined;
    }
    if (event.isError || typeof event.input.path !== "string") return undefined;
    const output = await runCheck(
      {
        tool_input: { file_path: targetPath(event.input.path, ctx.cwd) },
        cwd: ctx.cwd,
      },
      ctx.cwd,
      ctx.signal,
    );
    if (!output) return undefined;
    const note: TextContent = { type: "text", text: reportText(output) };
    return { content: [...event.content, note] };
  });
}
