#!/usr/bin/env -S deno run --no-prompt
/**
 * Report this Claude Code pane's prompt-cache expiry to Herdr as a $cache token.
 *
 * Claude Code exposes no cache lifetime, so it is derived from the transcript: the
 * selected assistant message's usage says which TTL was written, and the preceding
 * user entry's timestamp stands in for the request start (a conservative proxy --
 * the real start is slightly later, so the displayed expiry errs early).
 *
 * The token is registered with --ttl-ms set to the remaining lifetime, so Herdr
 * drops it exactly when the cache is due to expire. An absent $cache therefore
 * means "no reusable cache", and nothing has to tick down.
 *
 * Actions:
 *   stop     after a completed turn -- pick the new terminal entry, report the token
 *   session  SessionStart -- re-derive the token from the transcript, or clear it
 *   compact  PostCompact -- the cached prefix is gone, clear the token
 *
 * Selection rules (why each one exists is in the review that produced them):
 *   - group JSONL lines by message.id -- one line per content block, usage repeated
 *   - only this session's main chain, never a sidechain
 *   - skip transparent entries (usage all zero) -- they prove no cache event
 *   - skip non-terminal entries (tool_use, pause_turn)
 *   - only entries after the stored cursor, so a previous turn is never mistaken
 *     for the current one
 *   - read the top-level usage.cache_creation only, never sum usage.iterations[] --
 *     advisor iterations write their own 5m cache in there
 *   - a read-only turn takes its TTL from the last write in the transcript, so the
 *     only thing kept on disk is the cursor; everything else is derived each time
 */

const SOURCE = "claude-cache";
const TOKEN = "cache";
const BUDGET_MS = 1500;
const INTERVAL_MS = 100;
const TAIL_BYTES = 512 * 1024;
const NON_TERMINAL = new Set(["tool_use", "pause_turn"]);
const TTL_SECONDS: Record<string, number> = { "5m": 300, "1h": 3600 };
/** The token should die a moment before the cache does, never after. */
const SAFETY_MS = 2000;
const HERDR_TIMEOUT_MS = 5000;

const STATE_DIR = `${
  Deno.env.get("HOME") ?? "."
}/.local/state/herdr-cache-token`;

type Rec = Record<string, unknown>;

/** Everything below reads unknown JSON, so nothing is trusted without a guard. */
function rec(value: unknown): Rec | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Rec
    : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/** A token count. Anything that is not a positive finite number counts as zero. */
function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : 0;
}

/** Present but not exactly false means sidechain: an unknown shape is not main chain. */
function isSidechainFlag(value: unknown): boolean {
  return value !== undefined && value !== false;
}

type Group = {
  mid: string;
  uuid: string | null;
  firstIdx: number;
  stopReason: string | null;
  usage: Rec;
  ts: number | null;
};

type State = {
  cursor_mid?: string;
  cursor_uuid?: string;
  stale_after?: number;
};

function statePath(sessionId: string): string {
  // Keyed by pane as well as session: the same session resumed in two panes owns
  // two independent $cache tokens, and must not share one cursor.
  const key = `${Deno.env.get("HERDR_PANE_ID") ?? "nopane"}-${sessionId}`;
  const safe = [...key].filter((c) => /[A-Za-z0-9\-_]/.test(c)).join("");
  return `${STATE_DIR}/${safe}.json`;
}

/**
 * Persisted state, field by field. A value of the wrong shape is dropped rather
 * than carried into a comparison -- stale_after: null would compare as 0 and
 * silently disable the freshness guard. Fields written by earlier versions
 * (ttl, expires_at) are derived now, so loading simply forgets them.
 */
function loadState(sessionId: string): State {
  const state: State = {};
  try {
    const parsed = rec(JSON.parse(Deno.readTextFileSync(statePath(sessionId))));
    if (parsed === null) return state;
    const cursorMid = str(parsed.cursor_mid);
    if (cursorMid !== null) state.cursor_mid = cursorMid;
    const cursorUuid = str(parsed.cursor_uuid);
    if (cursorUuid !== null) state.cursor_uuid = cursorUuid;
    const staleAfter = parsed.stale_after;
    if (typeof staleAfter === "number" && Number.isFinite(staleAfter)) {
      state.stale_after = staleAfter;
    }
  } catch {
    return {};
  }
  return state;
}

/** True when the state reached disk. A lost cursor must stop us reporting. */
function saveState(sessionId: string, state: State): boolean {
  try {
    Deno.mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
    Deno.chmodSync(STATE_DIR, 0o700); // mode above only applies on creation
    const path = statePath(sessionId);
    const tmp = `${path}.${Deno.pid}.tmp`;
    Deno.writeTextFileSync(tmp, JSON.stringify(state), { mode: 0o600 });
    Deno.renameSync(tmp, path);
    return true;
  } catch {
    return false;
  }
}

function readTail(path: string): unknown[] {
  const size = Deno.statSync(path).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const buf = new Uint8Array(size - start);
  const file = Deno.openSync(path, { read: true });
  try {
    file.seekSync(start, Deno.SeekMode.Start);
    let filled = 0;
    while (filled < buf.length) {
      const read = file.readSync(buf.subarray(filled));
      if (read === null || read === 0) break;
      filled += read;
    }
    let data = buf.subarray(0, filled);
    if (start > 0) {
      const nl = data.indexOf(0x0a);
      data = nl >= 0 ? data.subarray(nl + 1) : new Uint8Array();
    }
    const objs: unknown[] = [];
    for (const line of new TextDecoder().decode(data).split("\n")) {
      if (line.trim().length === 0) continue;
      try {
        objs.push(JSON.parse(line));
      } catch {
        continue; // a partially written tail line is normal, not an error
      }
    }
    return objs;
  } finally {
    file.close();
  }
}

function toEpoch(ts: unknown): number | null {
  const text = str(ts);
  if (text === null) return null;
  const ms = Date.parse(text);
  return Number.isNaN(ms) ? null : ms / 1000;
}

function groupAssistants(objs: unknown[], sessionId: string): Group[] {
  const order: Group[] = [];
  const seen = new Map<string, Group>();
  for (let idx = 0; idx < objs.length; idx++) {
    const o = rec(objs[idx]);
    if (
      o === null || o.type !== "assistant" || isSidechainFlag(o.isSidechain)
    ) {
      continue;
    }
    const message = rec(o.message);
    if (message === null) continue;
    const mid = str(message.id);
    if (mid === null) continue;
    if (str(o.sessionId) !== sessionId) continue;
    let entry = seen.get(mid);
    if (entry === undefined) {
      entry = {
        mid,
        uuid: str(o.uuid),
        firstIdx: idx,
        stopReason: null,
        usage: {},
        ts: toEpoch(o.timestamp),
      };
      seen.set(mid, entry);
      order.push(entry);
    }
    const stopReason = str(message.stop_reason);
    if (stopReason !== null) entry.stopReason = stopReason;
    const usage = rec(message.usage);
    if (usage !== null) entry.usage = usage;
  }
  return order;
}

function isTransparent(usage: Rec): boolean {
  return !(
    count(usage.input_tokens) ||
    count(usage.cache_read_input_tokens) ||
    count(usage.cache_creation_input_tokens)
  );
}

function isTerminal(entry: Group): boolean {
  // A missing stop_reason means the message is still being written, not that it ended.
  return entry.stopReason !== null &&
    !NON_TERMINAL.has(entry.stopReason) &&
    !isTransparent(entry.usage);
}

/**
 * Newest usable entry strictly after the cursor; null when there is nothing new.
 *
 * minTs rejects entries recorded before a turn we already gave up waiting for,
 * so a late arrival cannot be mistaken for the turn that just ended.
 */
function newestTerminal(
  groups: Group[],
  cursorMid?: string,
  minTs?: number,
): Group | null {
  let start = 0;
  if (cursorMid !== undefined) {
    const found = groups.findLastIndex((g) => g.mid === cursorMid);
    if (found < 0) {
      // The cursor fell outside the tail window, so "after the cursor" is
      // unknowable. Guessing here is what would resurrect a previous turn.
      return null;
    }
    start = found + 1;
  }
  let candidates = groups.slice(start).filter(isTerminal);
  if (minTs !== undefined) {
    candidates = candidates.filter((g) => g.ts !== null && g.ts > minTs);
  }
  return candidates.at(-1) ?? null;
}

/** True when the per-TTL breakdown claims a write of either lifetime. */
function claimsWrite(usage: Rec): boolean {
  const creation = rec(usage.cache_creation) ?? {};
  return count(creation.ephemeral_5m_input_tokens) > 0 ||
    count(creation.ephemeral_1h_input_tokens) > 0;
}

/**
 * The TTL this message wrote its cache with, or null when it wrote none.
 *
 * The breakdown is only read when the total agrees that something was written;
 * a breakdown without a total contradicts itself, and a contradiction is unknown.
 */
function creationKind(usage: Rec): string | null {
  if (count(usage.cache_creation_input_tokens) === 0) return null;
  const creation = rec(usage.cache_creation) ?? {};
  // Both positive also lands on 5m: the shortest expiry wins.
  if (count(creation.ephemeral_5m_input_tokens)) return "5m";
  if (count(creation.ephemeral_1h_input_tokens)) return "1h";
  return null;
}

/**
 * Which TTL the cache this message touched was written with.
 *
 * A read-only refresh writes nothing of its own, so its TTL is that of the most
 * recent write in the same transcript. Walking back for it -- rather than
 * remembering it -- means no stored value can go stale and be inherited.
 *
 * Only that one case may inherit. A write whose breakdown is missing, and a turn
 * that touched no cache at all, are both unknown -- and unknown means clear.
 */
function ttlKind(groups: Group[], entry: Group): string | null {
  const own = creationKind(entry.usage);
  if (own !== null) return own;
  // Reaching here means the message wrote something we cannot name, wrote nothing
  // at all, or contradicts itself. Only the clean read-only refresh may inherit.
  const wroteNothing = count(entry.usage.cache_creation_input_tokens) === 0 &&
    !claimsWrite(entry.usage);
  const refreshed = count(entry.usage.cache_read_input_tokens) > 0;
  if (!wroteNothing || !refreshed) return null;
  const idx = groups.indexOf(entry);
  for (const g of groups.slice(0, idx).reverse()) {
    const kind = creationKind(g.usage);
    if (kind !== null) return kind;
  }
  return null;
}

/** Timestamp of the user entry that opened this request -- a conservative proxy. */
function requestStart(
  objs: unknown[],
  entry: Group,
  sessionId: string,
): number | null {
  for (let i = entry.firstIdx - 1; i >= 0; i--) {
    const o = rec(objs[i]);
    if (o === null || o.type !== "user" || isSidechainFlag(o.isSidechain)) {
      continue;
    }
    if (str(o.sessionId) !== sessionId) continue;
    // The nearest user entry is the one that opened this request. If it carries no
    // usable timestamp there is no start to derive; reaching further back would
    // borrow an older turn's clock.
    return toEpoch(o.timestamp);
  }
  return null;
}

async function herdr(...args: string[]): Promise<void> {
  const pane = Deno.env.get("HERDR_PANE_ID");
  if (pane === undefined || pane.length === 0) return;
  const binary = Deno.env.get("HERDR_BIN_PATH") || "herdr";
  const socket = Deno.env.get("HERDR_SOCKET_PATH");
  try {
    const command = new Deno.Command(binary, {
      args: [
        "pane",
        "report-metadata",
        pane,
        "--source",
        SOURCE,
        "--seq",
        String(
          BigInt(Date.now()) * 1000000n +
            BigInt(Math.floor((performance.now() % 1) * 1e6)),
        ),
        ...args,
      ],
      stdin: "null",
      stdout: "null",
      stderr: "null",
      clearEnv: true,
      env: socket === undefined ? {} : { HERDR_SOCKET_PATH: socket },
      signal: AbortSignal.timeout(HERDR_TIMEOUT_MS),
    });
    await command.spawn().status;
  } catch {
    // Reporting is best effort; a display hook never disturbs the session.
  }
}

function clearToken(): Promise<void> {
  return herdr("--clear-token", TOKEN);
}

async function reportExpiry(expiresAt: number): Promise<boolean> {
  const remainingMs = Math.trunc((expiresAt - Date.now() / 1000) * 1000) -
    SAFETY_MS;
  if (remainingMs <= 0) {
    await clearToken();
    return false;
  }
  const at = new Date(expiresAt * 1000);
  const label = `~${String(at.getHours()).padStart(2, "0")}:${
    String(at.getMinutes()).padStart(2, "0")
  }`;
  await herdr("--token", `${TOKEN}=${label}`, "--ttl-ms", String(remainingMs));
  return true;
}

/** Distinguishes "leave the cursor alone" from "there is no anchor to keep". */
const KEEP_CURSOR = Symbol("keep-cursor");

/**
 * Drop the token and the TTL it was derived from.
 *
 * A watermark advances the cursor without publishing anything, which covers two
 * cases: an entry that arrives after we gave up waiting must not be adopted as
 * the next turn's, and a cursor that has scrolled out of the tail window would
 * otherwise never be found again and strand the session in a permanent clear.
 */
async function failClosed(
  sessionId: string,
  state: State,
  watermark: Group | null | typeof KEEP_CURSOR = KEEP_CURSOR,
  staleAfter?: number,
): Promise<void> {
  await clearToken();
  if (watermark !== KEEP_CURSOR) {
    if (watermark === null) {
      // Nothing terminal in the window to anchor to. stale_after still guards
      // freshness, so drop the unfindable cursor instead of stalling a turn.
      delete state.cursor_mid;
      delete state.cursor_uuid;
    } else {
      state.cursor_mid = watermark.mid;
      state.cursor_uuid = watermark.uuid ?? undefined;
    }
  }
  if (staleAfter !== undefined) state.stale_after = staleAfter;
  if (!saveState(sessionId, state)) {
    // State we cannot rewrite must not survive: drop the file instead.
    try {
      Deno.removeSync(statePath(sessionId));
    } catch {
      // Nothing further can be done from here.
    }
  }
}

/** Derive the expiry from one assistant message and register the token. */
async function publish(
  sessionId: string,
  state: State,
  groups: Group[],
  objs: unknown[],
  entry: Group,
): Promise<void> {
  const kind = ttlKind(groups, entry);
  const start = requestStart(objs, entry, sessionId);
  if (kind === null || start === null) {
    await failClosed(sessionId, state);
    return;
  }
  const saved = saveState(sessionId, {
    cursor_mid: entry.mid,
    cursor_uuid: entry.uuid ?? undefined,
  });
  if (!saved) {
    // Without a persisted cursor the next Stop could re-adopt this entry.
    await clearToken();
    return;
  }
  await reportExpiry(start + TTL_SECONDS[kind]);
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function actionStop(payload: Rec, sessionId: string): Promise<void> {
  const path = str(payload.transcript_path);
  const state = loadState(sessionId);
  if (path === null || !existsSync(path)) {
    await failClosed(sessionId, state);
    return;
  }
  const cursor = state.cursor_mid;
  const staleAfter = state.stale_after;

  const deadline = Date.now() + BUDGET_MS;
  let entry: Group | null = null;
  let objs: unknown[] = [];
  let groups: Group[] = [];
  while (true) {
    objs = readTail(path);
    groups = groupAssistants(objs, sessionId);
    entry = newestTerminal(groups, cursor, staleAfter);
    if (entry !== null || Date.now() >= deadline) break;
    await sleep(INTERVAL_MS);
  }

  if (entry === null) {
    // The turn never landed, or the cursor is no longer in the window. Publishing
    // anything here would lie; re-seed the boundary so the next turn recovers,
    // and remember the moment we gave up so this turn's late write is not then
    // mistaken for the next turn's.
    await failClosed(
      sessionId,
      state,
      newestTerminal(groups),
      Date.now() / 1000,
    );
    return;
  }

  await publish(sessionId, state, groups, objs, entry);
}

/** Sources that continue an existing conversation, and so may still hold a cache. */
const RESUMING_SOURCES = new Set(["startup", "resume"]);

/** Seed the cursor so the first Stop cannot pick up a previous turn. */
async function actionSession(payload: Rec, sessionId: string): Promise<void> {
  const source = str(payload.source);
  const path = str(payload.transcript_path);
  const state = loadState(sessionId);

  // clear and compact discard the prefix; an absent or unfamiliar source is not
  // evidence that a cache survived, so it clears too.
  if (
    source === null || !RESUMING_SOURCES.has(source) || path === null ||
    !existsSync(path)
  ) {
    await failClosed(sessionId, state);
    return;
  }

  const objs = readTail(path);
  const groups = groupAssistants(objs, sessionId);
  const entry = newestTerminal(groups);
  if (entry === null) {
    await failClosed(sessionId, state);
    return;
  }
  // Herdr drops pane metadata when its server restarts, so the token is registered
  // again here -- derived afresh from the transcript rather than restored from a
  // stored expiry, which could outlive the state that justified it.
  await publish(sessionId, state, groups, objs, entry);
}

/** Compaction rewrites the prefix, so whatever was cached is unreachable. */
async function actionCompact(_payload: Rec, sessionId: string): Promise<void> {
  await failClosed(sessionId, loadState(sessionId));
}

function existsSync(path: string): boolean {
  try {
    Deno.statSync(path);
    return true;
  } catch {
    return false;
  }
}

async function readStdin(): Promise<string> {
  const chunks: Uint8Array[] = [];
  const buf = new Uint8Array(64 * 1024);
  while (true) {
    const read = await Deno.stdin.read(buf);
    if (read === null) break;
    chunks.push(buf.slice(0, read));
  }
  return new TextDecoder().decode(
    chunks.reduce((all, chunk) => {
      const merged = new Uint8Array(all.length + chunk.length);
      merged.set(all);
      merged.set(chunk, all.length);
      return merged;
    }, new Uint8Array()),
  );
}

async function main(): Promise<void> {
  const action = Deno.args[0] ?? "stop";
  if (Deno.env.get("HERDR_ENV") !== "1" || !Deno.env.get("HERDR_PANE_ID")) {
    return;
  }

  let payload: Rec = {};
  try {
    payload = rec(JSON.parse(await readStdin())) ?? {};
  } catch {
    payload = {};
  }

  // Without a session id the transcript cannot be filtered to this conversation,
  // so there is nothing this hook may honestly claim about the cache.
  const sessionId = str(payload.session_id);
  if (sessionId === null) {
    await clearToken();
    return;
  }

  const handlers: Record<string, (p: Rec, s: string) => Promise<void>> = {
    stop: actionStop,
    session: actionSession,
    compact: actionCompact,
  };
  try {
    const handler = handlers[action];
    if (handler === undefined) return;
    await handler(payload, sessionId);
  } catch {
    // A display-only hook must never disturb the session, but it must not leave
    // a token standing that it can no longer justify either.
    try {
      await clearToken();
    } catch {
      // Nothing further can be done from here.
    }
  }
}

await main();
Deno.exit(0);
