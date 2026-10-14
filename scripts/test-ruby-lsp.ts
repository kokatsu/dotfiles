const [executable, version] = Deno.args;
if (!executable || !version) {
  throw new Error("usage: test-ruby-lsp.ts <ruby-lsp> <version>");
}
const temporary = await Deno.makeTempDir({ prefix: "ruby-lsp-test-" });

interface Symbol {
  name: string;
  children?: Symbol[];
}

async function checkServer(root: string) {
  await Deno.mkdir(root);
  const source = `${root}/example.rb`;
  const text = "class NixPreview\n  def example\n    1\n  end\nend\n";
  await Deno.writeTextFile(source, text);
  const process = new Deno.Command(executable, {
    cwd: root,
    env: {
      HOME: root,
      XDG_CONFIG_HOME: `${root}/config`,
      XDG_CACHE_HOME: `${root}/cache`,
      XDG_DATA_HOME: `${root}/data`,
      XDG_STATE_HOME: `${root}/state`,
      GEM_HOME: `${root}/empty-gems`,
      GEM_PATH: `${root}/empty-gems`,
    },
    stdin: "piped",
    stdout: "piped",
    stderr: "inherit",
  }).spawn();
  const writer = process.stdin.getWriter();
  const reader = process.stdout.getReader();
  let buffer = new Uint8Array(0);
  let exited = false;
  const status = process.status.then((result) => {
    exited = true;
    return result;
  });

  async function send(message: Record<string, unknown>) {
    const body = new TextEncoder().encode(JSON.stringify(message));
    await writer.write(
      new TextEncoder().encode(`Content-Length: ${body.length}\r\n\r\n`),
    );
    await writer.write(body);
  }

  async function response<T>(identifier: number): Promise<T> {
    let timer: ReturnType<typeof setTimeout>;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(
        () => reject(new Error("Ruby LSP response timed out")),
        15000,
      );
    });
    try {
      while (true) {
        const separator = buffer.findIndex((byte, index) =>
          byte === 13 && buffer[index + 1] === 10 && buffer[index + 2] === 13 &&
          buffer[index + 3] === 10
        );
        if (separator >= 0) {
          const headers = new TextDecoder().decode(
            buffer.subarray(0, separator),
          );
          const length = Number(headers.match(/Content-Length:\s*(\d+)/i)?.[1]);
          if (!Number.isFinite(length)) {
            throw new Error("Missing LSP Content-Length");
          }
          const end = separator + 4 + length;
          if (buffer.length >= end) {
            const message = JSON.parse(
              new TextDecoder().decode(buffer.subarray(separator + 4, end)),
            );
            buffer = buffer.slice(end);
            if (message.id === identifier) {
              if (message.error) throw new Error(JSON.stringify(message.error));
              return message.result;
            }
            continue;
          }
        }
        const chunk = await Promise.race([reader.read(), timeout]);
        if (chunk.done) throw new Error("Ruby LSP exited before its response");
        const next = new Uint8Array(buffer.length + chunk.value.length);
        next.set(buffer);
        next.set(chunk.value, buffer.length);
        buffer = next;
      }
    } finally {
      clearTimeout(timer!);
    }
  }

  try {
    const uri = new URL(`file://${source}`).href;
    await send({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        processId: Deno.pid,
        rootUri: new URL(`file://${root}`).href,
        capabilities: {},
        initializationOptions: { formatter: "rubocop", linters: ["rubocop"] },
      },
    });
    const initialized = await response<{ serverInfo: { version: string } }>(1);
    if (initialized.serverInfo.version !== version) {
      throw new Error("Unexpected Ruby LSP version");
    }
    await send({ jsonrpc: "2.0", method: "initialized", params: {} });
    await send({
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: {
        textDocument: { uri, languageId: "ruby", version: 1, text },
      },
    });
    await send({
      jsonrpc: "2.0",
      id: 2,
      method: "textDocument/documentSymbol",
      params: { textDocument: { uri } },
    });
    const symbols = await response<Symbol[]>(2);
    if (
      symbols[0]?.name !== "NixPreview" ||
      symbols[0].children?.[0]?.name !== "example"
    ) {
      throw new Error(`Ruby symbols failed: ${JSON.stringify(symbols)}`);
    }
    await send({ jsonrpc: "2.0", id: 3, method: "shutdown", params: null });
    await response(3);
    await send({ jsonrpc: "2.0", method: "exit", params: null });
    if (!(await status).success) throw new Error("Ruby LSP shutdown failed");
  } finally {
    if (!exited) process.kill("SIGTERM");
    await status;
    await writer.close().catch(() => {});
    await reader.cancel().catch(() => {});
  }
}

try {
  for (const name of ["first", "second"]) {
    await checkServer(`${temporary}/${name}`);
  }
  console.log(
    "Ruby LSP: isolated gems, initialization and document symbols in two roots passed",
  );
} finally {
  await Deno.remove(temporary, { recursive: true });
}
