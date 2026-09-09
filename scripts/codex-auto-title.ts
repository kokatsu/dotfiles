type JsonObject = Record<string, unknown>;

export interface RpcClient {
  request(method: string, params: JsonObject): Promise<unknown>;
  close(): Promise<void>;
}

interface TurnNotification {
  type?: unknown;
  "thread-id"?: unknown;
  cwd?: unknown;
  "input-messages"?: unknown;
}

interface ThreadInfo extends JsonObject {
  name?: unknown;
  ephemeral?: unknown;
  parentThreadId?: unknown;
  gitInfo?: unknown;
}

const MAX_TITLE_GRAPHEMES = 40;

function graphemes(value: string): string[] {
  const segmenter = new Intl.Segmenter("ja", { granularity: "grapheme" });
  return [...segmenter.segment(value)].map((part) => part.segment);
}

function truncate(value: string, maximum: number): string {
  const parts = graphemes(value);
  if (parts.length <= maximum) return value;
  if (maximum <= 1) return "…";
  return `${parts.slice(0, maximum - 1).join("")}…`;
}

function fallbackName(cwd: unknown): string {
  if (typeof cwd !== "string") return "Codex session";
  const parts = cwd.replace(/[\\/]+$/, "").split(/[\\/]/);
  return parts.at(-1) || "Codex session";
}

function branchIssue(branch: unknown): string | undefined {
  if (typeof branch !== "string") return undefined;
  return branch.match(/(?:^|[/_-])#?(\d{1,7})(?:$|[/_-])/)?.[1];
}

export function makeTitle(
  messages: unknown,
  cwd: unknown,
  branch: unknown,
): string {
  const prompt = Array.isArray(messages)
    ? messages.filter((item): item is string => typeof item === "string").join(
      " ",
    )
    : "";
  const normalized = prompt
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/https?:\/\/\S+/g, " ")
    .replace(/[\p{Cc}\p{Cf}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[。．.!！?？,:：;；、\s]+$/u, "");
  const issue = branchIssue(branch);
  const prefix = issue ? `#${issue} ` : "";
  const base = normalized || fallbackName(cwd);
  return `${prefix}${
    truncate(base, MAX_TITLE_GRAPHEMES - graphemes(prefix).length)
  }`;
}

function unwrapThread(response: unknown): ThreadInfo | undefined {
  if (typeof response !== "object" || response === null) return undefined;
  const object = response as JsonObject;
  const candidate = object.thread ?? object;
  if (typeof candidate !== "object" || candidate === null) return undefined;
  return candidate as ThreadInfo;
}

function isUnnamedRootThread(
  thread: ThreadInfo | undefined,
): thread is ThreadInfo {
  if (!thread || thread.ephemeral === true) return false;
  if (thread.parentThreadId !== undefined && thread.parentThreadId !== null) {
    return false;
  }
  return typeof thread.name !== "string" || thread.name.trim() === "";
}

export async function setAutomaticTitle(
  notification: TurnNotification,
  client: RpcClient,
): Promise<boolean> {
  if (notification.type !== "agent-turn-complete") return false;
  if (typeof notification["thread-id"] !== "string") return false;

  const threadId = notification["thread-id"];
  const initial = unwrapThread(
    await client.request("thread/read", { threadId, includeTurns: false }),
  );
  if (!isUnnamedRootThread(initial)) return false;

  const gitInfo =
    typeof initial.gitInfo === "object" && initial.gitInfo !== null
      ? initial.gitInfo as JsonObject
      : undefined;
  const title = makeTitle(
    notification["input-messages"],
    notification.cwd,
    gitInfo?.branch,
  );

  // Re-read immediately before writing so a concurrent /rename always wins.
  const current = unwrapThread(
    await client.request("thread/read", { threadId, includeTurns: false }),
  );
  if (!isUnnamedRootThread(current)) return false;

  await client.request("thread/name/set", { threadId, name: title });
  return true;
}

class BufferedConnection {
  readonly #connection: Deno.Conn;
  #buffer = new Uint8Array();

  constructor(connection: Deno.Conn) {
    this.#connection = connection;
  }

  async readExactly(length: number): Promise<Uint8Array> {
    while (this.#buffer.length < length) await this.#readMore();
    const result = this.#buffer.slice(0, length);
    this.#buffer = this.#buffer.slice(length);
    return result;
  }

  async readThrough(
    delimiter: Uint8Array,
    maximum: number,
  ): Promise<Uint8Array> {
    while (true) {
      const index = findBytes(this.#buffer, delimiter);
      if (index >= 0) {
        const end = index + delimiter.length;
        const result = this.#buffer.slice(0, end);
        this.#buffer = this.#buffer.slice(end);
        return result;
      }
      if (this.#buffer.length >= maximum) {
        throw new Error("app-server WebSocket response headers are too large");
      }
      await this.#readMore();
    }
  }

  async #readMore(): Promise<void> {
    const chunk = new Uint8Array(4096);
    const length = await this.#connection.read(chunk);
    if (length === null) throw new Error("app-server WebSocket closed");
    const combined = new Uint8Array(this.#buffer.length + length);
    combined.set(this.#buffer);
    combined.set(chunk.subarray(0, length), this.#buffer.length);
    this.#buffer = combined;
  }
}

function findBytes(haystack: Uint8Array, needle: Uint8Array): number {
  outer:
  for (let index = 0; index <= haystack.length - needle.length; index++) {
    for (let offset = 0; offset < needle.length; offset++) {
      if (haystack[index + offset] !== needle[offset]) continue outer;
    }
    return index;
  }
  return -1;
}

async function writeAll(
  connection: Deno.Conn,
  bytes: Uint8Array,
): Promise<void> {
  let offset = 0;
  while (offset < bytes.length) {
    offset += await connection.write(bytes.subarray(offset));
  }
}

function encodeFrame(opcode: number, payload: Uint8Array): Uint8Array {
  const extendedLength = payload.length <= 125
    ? 0
    : payload.length <= 0xffff
    ? 2
    : 8;
  const header = new Uint8Array(2 + extendedLength + 4);
  header[0] = 0x80 | opcode;
  header[1] = 0x80 |
    (extendedLength === 0 ? payload.length : extendedLength === 2 ? 126 : 127);
  const view = new DataView(header.buffer);
  if (extendedLength === 2) view.setUint16(2, payload.length);
  if (extendedLength === 8) view.setBigUint64(2, BigInt(payload.length));
  const maskOffset = 2 + extendedLength;
  const mask = crypto.getRandomValues(new Uint8Array(4));
  header.set(mask, maskOffset);

  const frame = new Uint8Array(header.length + payload.length);
  frame.set(header);
  for (let index = 0; index < payload.length; index++) {
    frame[header.length + index] = payload[index] ^ mask[index % 4];
  }
  return frame;
}

export class AppServerClient implements RpcClient {
  readonly #connection: Deno.Conn;
  readonly #buffered: BufferedConnection;
  readonly #encoder = new TextEncoder();
  readonly #decoder = new TextDecoder();
  #nextId = 1;
  #closed = false;

  private constructor(connection: Deno.Conn, signal?: AbortSignal) {
    this.#connection = connection;
    this.#buffered = new BufferedConnection(connection);
    signal?.addEventListener("abort", () => this.#closeConnection(), {
      once: true,
    });
  }

  static async connect(
    socket: string,
    signal?: AbortSignal,
  ): Promise<AppServerClient> {
    const connection = await Deno.connect({ transport: "unix", path: socket });
    const client = new AppServerClient(connection, signal);
    try {
      await client.#handshake();
      await client.request("initialize", {
        clientInfo: { name: "codex-auto-title", version: "1.0.0" },
        capabilities: {},
      });
      await client.#write({ method: "initialized", params: {} });
      return client;
    } catch (error) {
      client.#closeConnection();
      throw error;
    }
  }

  async #handshake(): Promise<void> {
    const nonce = crypto.getRandomValues(new Uint8Array(16));
    const key = btoa(String.fromCharCode(...nonce));
    const request = [
      "GET / HTTP/1.1",
      "Host: localhost",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Key: ${key}`,
      "Sec-WebSocket-Version: 13",
      "",
      "",
    ].join("\r\n");
    await writeAll(this.#connection, this.#encoder.encode(request));

    const rawHeaders = await this.#buffered.readThrough(
      this.#encoder.encode("\r\n\r\n"),
      16 * 1024,
    );
    const lines = this.#decoder.decode(rawHeaders).trim().split("\r\n");
    if (!/^HTTP\/1\.1 101(?: |$)/.test(lines[0] ?? "")) {
      throw new Error(`app-server rejected WebSocket upgrade: ${lines[0]}`);
    }
    const headers = new Map<string, string>();
    for (const line of lines.slice(1)) {
      const separator = line.indexOf(":");
      if (separator < 0) continue;
      headers.set(
        line.slice(0, separator).trim().toLowerCase(),
        line.slice(separator + 1).trim(),
      );
    }
    const digest = await crypto.subtle.digest(
      "SHA-1",
      this.#encoder.encode(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`),
    );
    const expectedAccept = btoa(
      String.fromCharCode(...new Uint8Array(digest)),
    );
    if (headers.get("sec-websocket-accept") !== expectedAccept) {
      throw new Error("app-server returned an invalid WebSocket accept key");
    }
  }

  async #write(message: JsonObject): Promise<void> {
    await writeAll(
      this.#connection,
      encodeFrame(0x1, this.#encoder.encode(JSON.stringify(message))),
    );
  }

  async #readMessage(): Promise<string> {
    const fragments: Uint8Array[] = [];
    while (true) {
      const header = await this.#buffered.readExactly(2);
      const final = (header[0] & 0x80) !== 0;
      const opcode = header[0] & 0x0f;
      const masked = (header[1] & 0x80) !== 0;
      let length = header[1] & 0x7f;
      if (length === 126) {
        const extended = await this.#buffered.readExactly(2);
        length = new DataView(extended.buffer).getUint16(0);
      } else if (length === 127) {
        const extended = await this.#buffered.readExactly(8);
        const value = new DataView(extended.buffer).getBigUint64(0);
        if (value > BigInt(Number.MAX_SAFE_INTEGER)) {
          throw new Error("app-server WebSocket frame is too large");
        }
        length = Number(value);
      }
      const mask = masked ? await this.#buffered.readExactly(4) : undefined;
      const payload = await this.#buffered.readExactly(length);
      if (mask) {
        for (let index = 0; index < payload.length; index++) {
          payload[index] ^= mask[index % 4];
        }
      }

      if (opcode === 0x8) throw new Error("app-server closed the WebSocket");
      if (opcode === 0x9) {
        await writeAll(this.#connection, encodeFrame(0xa, payload));
        continue;
      }
      if (opcode === 0xa) continue;
      if (opcode !== 0x0 && opcode !== 0x1) {
        throw new Error(`unsupported app-server WebSocket opcode: ${opcode}`);
      }
      fragments.push(payload);
      if (!final) continue;

      const size = fragments.reduce(
        (sum, fragment) => sum + fragment.length,
        0,
      );
      const message = new Uint8Array(size);
      let offset = 0;
      for (const fragment of fragments) {
        message.set(fragment, offset);
        offset += fragment.length;
      }
      return this.#decoder.decode(message);
    }
  }

  async request(method: string, params: JsonObject): Promise<unknown> {
    const id = this.#nextId++;
    await this.#write({ id, method, params });
    while (true) {
      const response = JSON.parse(await this.#readMessage()) as JsonObject;
      if (response.id !== id) continue;
      if (response.error !== undefined) {
        throw new Error(
          `app-server request failed: ${JSON.stringify(response.error)}`,
        );
      }
      return response.result;
    }
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    try {
      await writeAll(this.#connection, encodeFrame(0x8, new Uint8Array()));
    } catch {
      // The app-server may have already closed the connection.
    }
    this.#closeConnection();
  }

  #closeConnection(): void {
    if (this.#closed) return;
    this.#closed = true;
    try {
      this.#connection.close();
    } catch {
      // The timeout and normal cleanup may race.
    }
  }
}

if (import.meta.main) {
  const [rawNotification] = Deno.args;
  const socket = Deno.env.get("CODEX_AUTO_TITLE_SOCKET");
  if (rawNotification && socket) {
    let client: AppServerClient | undefined;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3_000);
    try {
      const notification = JSON.parse(rawNotification) as TurnNotification;
      client = await AppServerClient.connect(socket, controller.signal);
      await setAutomaticTitle(notification, client);
    } catch (error) {
      if (Deno.env.get("CODEX_AUTO_TITLE_DEBUG") === "1") {
        console.error(
          `codex-auto-title: ${
            error instanceof Error ? error.message : "unknown error"
          }`,
        );
      }
    } finally {
      clearTimeout(timeout);
      await client?.close();
    }
  }
}
