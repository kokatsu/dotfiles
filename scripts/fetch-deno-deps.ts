interface Manifest {
  entrypoints: string[];
  assets: Record<string, string>;
  config?: Record<string, unknown>;
}

interface Graph {
  roots: string[];
  modules: {
    specifier: string;
    local?: string;
    mediaType?: string;
    error?: string;
    dependencies?: { code?: { specifier: string } }[];
  }[];
  redirects: Record<string, string>;
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
const moduleMap: Record<string, { path: string; mediaType: string }> = {};
const redirects: Record<string, string> = {};

async function command(args: string[]): Promise<string> {
  const result = await new Deno.Command(Deno.execPath(), {
    args,
    stdout: "piped",
    stderr: "inherit",
  }).output();
  if (!result.success) throw new Error(`deno ${args[0]} failed`);
  return new TextDecoder().decode(result.stdout);
}

await Deno.mkdir(`${destination}/modules`, { recursive: true });
await command([
  "cache",
  "--allow-import",
  "--vendor=false",
  "--lock=deno.lock",
  `--frozen-lockfile=${Deno.env.get("DENO_DEPS_FROZEN") === "1"}`,
  ...manifest.entrypoints,
]);

for (const entrypoint of manifest.entrypoints) {
  const graph: Graph = JSON.parse(
    await command([
      "info",
      "--json",
      "--allow-import",
      "--vendor=false",
      entrypoint,
    ]),
  );
  Object.assign(redirects, graph.redirects);
  const bySpecifier = new Map(
    graph.modules.map((module) => [module.specifier, module]),
  );
  const required = new Set<string>();
  const visit = (specifier: string): void => {
    while (graph.redirects[specifier]) specifier = graph.redirects[specifier];
    if (required.has(specifier)) return;
    required.add(specifier);
    const module = bySpecifier.get(specifier);
    if (!module) throw new Error(`Missing graph module: ${specifier}`);
    for (const dependency of module.dependencies ?? []) {
      if (dependency.code) visit(dependency.code.specifier);
    }
  };
  // Deno info also reports declaration-only imports; emit does not load those.
  for (const root of graph.roots) visit(root);
  for (const specifier of required) {
    const module = bySpecifier.get(specifier)!;
    if (module.error) throw new Error(module.error);
    if (!module.specifier.startsWith("https://")) continue;
    if (!module.local) throw new Error(`No local module: ${module.specifier}`);
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(module.specifier),
    );
    const hash = Array.from(new Uint8Array(digest))
      .map((byte) => byte.toString(16).padStart(2, "0")).join("");
    const path = `modules/${hash}`;
    // Cache timestamps and response headers must not change the dependency hash.
    const source = (await Deno.readTextFile(module.local))
      .replace(/\n?\/\/ denoCacheMetadata=.*\s*$/, "");
    await Deno.writeTextFile(`${destination}/${path}`, source);
    moduleMap[module.specifier] = {
      path,
      mediaType: module.mediaType ?? "JavaScript",
    };
  }
}

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
await Deno.mkdir(`${destination}/assets`, { recursive: true });
for (const [name, url] of Object.entries(manifest.assets)) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  const path = `${destination}/assets/${name}`;
  await Deno.mkdir(path.slice(0, path.lastIndexOf("/")), { recursive: true });
  await Deno.writeFile(path, new Uint8Array(await response.arrayBuffer()));
}
await Deno.writeTextFile(
  `${destination}/module-map.json`,
  JSON.stringify({ modules: moduleMap, redirects }, null, 2) + "\n",
);
