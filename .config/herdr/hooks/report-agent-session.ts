#!/usr/bin/env -S deno run --no-prompt
/**
 * Report a Claude Code or Codex session's identity to Herdr at SessionStart.
 *
 * This replaces the Python hooks that `herdr integration install` generated
 * per agent. Those were marked "managed by herdr" and were rewritten by every
 * reinstall; the two differed only in which payloads they refused and whether
 * they sent a transcript path, so they collapse into one script here.
 *
 * They also spoke JSON-RPC to the Herdr socket themselves. This calls
 * `herdr pane report-agent-session` instead, so the request id, the connect and
 * the discarded reply are Herdr's problem. The params the CLI puts on the wire
 * were compared against the old request and match field for field, seq included
 * -- only the client-side request id differs, which no report carries.
 *
 * Argv: <agent> <herdr binary>. The launcher resolves the binary so the same
 * absolute path can be handed to --allow-run.
 */

/** The old hook's socket timeout. A local report answers in about 10ms. */
const TIMEOUT_MS = 500;

type Rec = Record<string, unknown>;

interface Profile {
  /** Herdr keys pane metadata by source, so these strings must not drift. */
  source: string;
  /** Only Claude Code exposes a transcript to point Herdr at. */
  reportsPath: boolean;
  /** Payloads this agent must not report at all. */
  skips: (payload: Rec, event: string) => boolean;
}

const PROFILES: Record<string, Profile> = {
  claude: {
    source: "herdr:claude",
    reportsPath: true,
    skips: (payload, event) =>
      // A subagent runs under its own id and must not claim the pane's session.
      str(payload.agent_id) !== null ||
      // SubagentStop is a completion event. Older Herdr integrations mapped it
      // to durable working, but Claude recap/away-summary can emit it after the
      // main turn has already stopped. Never let it revive an idle pane.
      event === "SubagentStop",
  },
  codex: {
    source: "herdr:codex",
    reportsPath: false,
    // Codex routes other events through the same hook. An absent name is still
    // accepted, as it was before, so only a named non-SessionStart is refused.
    skips: (_payload, event) => event !== "" && event !== "SessionStart",
  },
};

function rec(value: unknown): Rec | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Rec
    : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

async function readStdin(): Promise<string> {
  return await new Response(Deno.stdin.readable).text();
}

async function main(): Promise<void> {
  const profile = PROFILES[Deno.args[0] ?? ""];
  const binary = Deno.args[1];
  if (profile === undefined || binary === undefined) return;

  const pane = Deno.env.get("HERDR_PANE_ID");
  const socket = Deno.env.get("HERDR_SOCKET_PATH");
  if (Deno.env.get("HERDR_ENV") !== "1" || !pane || !socket) return;

  let payload: Rec = {};
  try {
    payload = rec(JSON.parse(await readStdin())) ?? {};
  } catch {
    payload = {};
  }

  // The hook contract types this and agent_id as strings, so both are read
  // through the same guard and anything else counts as absent. The hooks this
  // replaces applied Python truthiness to the raw value instead, which agreed
  // for strings and for a missing field and parted only on shapes neither agent
  // sends: {} and [] were falsy there, and a number stringified.
  const event = str(payload.hook_event_name) ?? "";
  if (profile.skips(payload, event)) return;

  // Without a session id there is no identity to report, which is the one thing
  // this hook exists to send.
  const sessionId = str(payload.session_id);
  if (sessionId === null) return;

  const args = [
    "pane",
    "report-agent-session",
    pane,
    "--source",
    profile.source,
    "--agent",
    Deno.args[0],
    // time.time_ns() in the old hook. Temporal.Now is epoch nanoseconds too, so
    // the two orderings interleave correctly across a restart.
    "--seq",
    String(Temporal.Now.instant().epochNanoseconds),
    "--agent-session-id",
    sessionId,
  ];
  const path = profile.reportsPath ? str(payload.transcript_path) : null;
  if (path !== null) args.push("--agent-session-path", path);
  const startSource = event === "SessionStart" ? str(payload.source) : null;
  if (startSource !== null) args.push("--session-start-source", startSource);

  const command = new Deno.Command(binary, {
    args,
    stdin: "null",
    stdout: "null",
    stderr: "null",
    clearEnv: true,
    env: { HERDR_SOCKET_PATH: socket },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  await command.spawn().status;
}

try {
  await main();
} catch {
  // Reporting is best effort; a session must start whether or not Herdr hears.
}
Deno.exit(0);
