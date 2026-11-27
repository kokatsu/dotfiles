interface Manifest {
  entrypoints: string[];
  config?: Record<string, unknown>;
}

const [manifestPath, destination] = Deno.args;
if (!manifestPath || !destination) {
  throw new Error("usage: fetch-deno-deps.ts <manifest> <destination>");
}
const manifest: Manifest = JSON.parse(await Deno.readTextFile(manifestPath));
if (manifest.config) {
  const config = JSON.parse(await Deno.readTextFile("deno.json"));
  await Deno.writeTextFile(
    "deno.json",
    JSON.stringify({ ...config, ...manifest.config }, null, 2) + "\n",
  );
}

async function command(args: string[]): Promise<void> {
  const result = await new Deno.Command(Deno.execPath(), {
    args,
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) throw new Error(`deno ${args[0]} failed`);
}

await Deno.mkdir(destination, { recursive: true });
await command([
  "cache",
  "--allow-import",
  "--vendor=false",
  "--lock=deno.lock",
  `--frozen-lockfile=${Deno.env.get("DENO_DEPS_FROZEN") === "1"}`,
  ...manifest.entrypoints,
]);
await command([
  "cache",
  "--allow-import",
  "--vendor",
  "--lock=deno.lock",
  "--frozen-lockfile",
  ...manifest.entrypoints,
]);
await Deno.mkdir("vendor", { recursive: true });
const copied = await new Deno.Command("cp", {
  args: ["-R", "vendor", `${destination}/vendor`],
}).output();
if (!copied.success) throw new Error(new TextDecoder().decode(copied.stderr));
if (manifest.config) {
  await Deno.copyFile("deno.json", `${destination}/config.json`);
  if (await Deno.stat("node_modules").then(() => true).catch(() => false)) {
    const npm = await new Deno.Command("cp", {
      args: ["-R", "node_modules", `${destination}/node_modules`],
    }).output();
    if (!npm.success) throw new Error(new TextDecoder().decode(npm.stderr));
  }
}
await Deno.copyFile("deno.lock", `${destination}/deno.lock`);
