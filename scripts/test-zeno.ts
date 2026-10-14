const [plugin] = Deno.args;
if (!plugin) throw new Error("usage: test-zeno.ts <plugin-directory>");
const temporary = await Deno.makeTempDir({ prefix: "zeno-test-" });
await Deno.mkdir(`${temporary}/config/zeno`, { recursive: true });
await Deno.writeTextFile(
  `${temporary}/config/zeno/config.ts`,
  'import { defineConfig } from "jsr:@yuki-yano/zeno@^0.4.1";\nexport default defineConfig(() => ({ snippets: [{ name: "Nix", keyword: "np", snippet: "nix-preview" }] }));\n',
);
const socketPath = `${temporary}/zeno.sock`;
const env = {
  HOME: temporary,
  XDG_CONFIG_HOME: `${temporary}/config`,
  XDG_DATA_HOME: `${temporary}/data`,
  XDG_CACHE_HOME: `${temporary}/cache`,
  XDG_STATE_HOME: `${temporary}/state`,
  DENO_DIR: `${temporary}/deno-cache`,
  ZENO_HOME: `${temporary}/config/zeno`,
  ZENO_ROOT: plugin,
  ZENO_SOCK: socketPath,
  ZENO_DISABLE_AUTOMATIC_WORKSPACE_LOOKUP: "1",
};
let server: Deno.ChildProcess | undefined;
let exited = false;
let status: Promise<Deno.CommandStatus> | undefined;

try {
  const cli = await new Deno.Command(`${plugin}/bin/zeno`, {
    args: ["--zeno-mode", "snippet-list"],
    env,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (
    !cli.success ||
    !new TextDecoder().decode(cli.stdout).includes("nix-preview")
  ) {
    throw new Error(
      `Zeno snippet failed: ${new TextDecoder().decode(cli.stderr)}`,
    );
  }
  server = new Deno.Command(`${plugin}/bin/zeno-server`, {
    env,
    stdout: "inherit",
    stderr: "inherit",
  }).spawn();
  status = server.status.then((result) => {
    exited = true;
    return result;
  });
  let available = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    available = await Deno.stat(socketPath).then(() => true).catch(() => false);
    if (available || exited) break;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (!available) throw new Error("Zeno socket did not start");
  const connection = await Deno.connect({
    transport: "unix",
    path: socketPath,
  });
  await connection.write(
    new TextEncoder().encode(
      JSON.stringify({ args: ["--zeno-mode", "snippet-list"] }),
    ),
  );
  await connection.closeWrite();
  let response = "";
  const buffer = new Uint8Array(4096);
  while (true) {
    const count = await connection.read(buffer);
    if (count === null) break;
    response += new TextDecoder().decode(buffer.subarray(0, count));
  }
  connection.close();
  if (!response.includes("nix-preview")) {
    throw new Error("Zeno socket snippet failed");
  }
  const database = await new Deno.Command(Deno.execPath(), {
    args: [
      "eval",
      "--config",
      `${plugin}/deno.json`,
      "--vendor",
      "--cached-only",
      "--frozen-lockfile",
      "--node-modules-dir=manual",
      `const {createSQLiteStore} = await import(${
        JSON.stringify(`file://${plugin}/src/history/sqlite-store.ts`)
      }); const store = await createSQLiteStore({databasePath:${
        JSON.stringify(`${temporary}/history.sqlite`)
      }}); await store.close();`,
    ],
    env,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!database.success) {
    throw new Error(new TextDecoder().decode(database.stderr));
  }
  console.log(
    "Zeno offline runtime: TypeScript config, CLI, socket and SQLite passed",
  );
} finally {
  if (server && !exited) server.kill("SIGTERM");
  if (status) await status;
  await Deno.remove(temporary, { recursive: true });
}
