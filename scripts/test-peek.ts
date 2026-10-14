const [plugin] = Deno.args;
if (!plugin) throw new Error("usage: test-peek.ts <plugin-directory>");
const temporary = await Deno.makeTempDir({ prefix: "peek-test-" });
const logfile = `${temporary}/peek.log`;
const browser = `${temporary}/browser`;
const addressFile = `${temporary}/address`;
await Deno.writeTextFile(
  browser,
  `#!${
    Deno.env.get("PEEK_TEST_SHELL") ?? "/bin/sh"
  }\nprintf '%s' "$1" > '${addressFile}'\n`,
);
await Deno.chmod(browser, 0o700);
const launcher = Deno.build.os === "darwin" ? `${temporary}/open` : browser;
if (Deno.build.os === "darwin") {
  // open@v0.0.6 uses `open -a <app> <url>` even for an explicit executable.
  await Deno.writeTextFile(
    launcher,
    `#!${Deno.env.get("PEEK_TEST_SHELL") ?? "/bin/sh"}\nexec "$2" "$3"\n`,
  );
  await Deno.chmod(launcher, 0o700);
}
const process = new Deno.Command(Deno.execPath(), {
  cwd: plugin,
  args: [
    "run",
    "--no-config",
    "--no-lock",
    "--cached-only",
    "--no-remote",
    "--no-npm",
    "--allow-read",
    "--allow-write",
    "--allow-env",
    "--allow-net=127.0.0.1,localhost,0.0.0.0",
    `--allow-run=${launcher}`,
    "public/main.bundle.js",
    `--app=${JSON.stringify([browser])}`,
    `--logfile=${logfile}`,
    "--theme=dark",
    "--syntax",
  ],
  env: {
    DENO_DIR: `${temporary}/deno-cache`,
    PATH: `${temporary}:${Deno.env.get("PATH") ?? ""}`,
  },
  stdin: "piped",
  stdout: "inherit",
  stderr: "inherit",
}).spawn();
let exited = false;
const status = process.status.then((result) => {
  exited = true;
  return result;
});
const writer = process.stdin.getWriter();
let socket: WebSocket | undefined;

async function send(chunks: string[]) {
  for (const chunk of chunks) {
    const data = new TextEncoder().encode(chunk);
    const header = new Uint8Array(4);
    new DataView(header.buffer).setUint32(0, data.length);
    await writer.write(header);
    await writer.write(data);
  }
}

try {
  let address: string | undefined;
  for (let attempt = 0; attempt < 100; attempt++) {
    if (await Deno.stat(addressFile).then(() => true).catch(() => false)) {
      address = new URL(await Deno.readTextFile(addressFile)).host;
    }
    if (address) break;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (!address) throw new Error("Peek did not start within 5 seconds");
  const root = `http://${address}`;
  for (
    const asset of [
      "index.html",
      "script.bundle.js",
      "mermaid.min.js",
      "github-markdown.min.css",
      "katex.min.css",
      "fonts/KaTeX_Main-Regular.woff2",
    ]
  ) {
    const response = await fetch(`${root}/${asset}`);
    if (!response.ok) throw new Error(`Asset failed: ${asset}`);
    const data = await response.arrayBuffer();
    if (!data.byteLength) throw new Error(`Empty asset: ${asset}`);
    if (
      asset === "index.html" &&
      !new TextDecoder().decode(data).includes('rel="icon"')
    ) {
      throw new Error("Missing favicon");
    }
  }
  socket = new WebSocket(`ws://${address}`);
  socket.binaryType = "arraybuffer";
  await new Promise<void>((resolve, reject) => {
    socket!.onopen = () => resolve();
    socket!.onerror = () => reject(new Error("WebSocket connection failed"));
  });
  const message = new Promise<string>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Render timed out")), 5000);
    socket!.onmessage = (event) => {
      clearTimeout(timer);
      resolve(new TextDecoder().decode(event.data));
    };
  });
  await send(["show", "# Nix preview\n\n```js\nconst x = 1;\n```\n\n$1+1$\n"]);
  const result = JSON.parse(await message);
  if (
    !/<h1[^>]*>Nix preview<\/h1>/.test(result.html) ||
    !result.html.includes("katex")
  ) {
    throw new Error("Markdown or math rendering failed");
  }
  console.log(
    "Peek offline runtime: assets, favicon, Markdown and math passed",
  );
} finally {
  socket?.close();
  if (!exited) process.kill("SIGTERM");
  await status;
  await writer.close().catch(() => {});
  await Deno.remove(temporary, { recursive: true });
}
