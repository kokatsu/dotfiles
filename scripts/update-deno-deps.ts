import { baseSource, checked, run } from "./hash-update-lib.ts";

const [base] = Deno.args;
if (!base) throw new Error("usage: update-deno-deps.ts <base-ref|--all>");
const root = Deno.cwd();
const lock = JSON.parse(await Deno.readTextFile("flake.lock"));
const previous = base === "--all"
  ? undefined
  : JSON.parse(await baseSource(base, "flake.lock", run));
const changed = base === "--all" ? [] : (await checked(run, "git", [
  "diff",
  "--name-only",
  base,
  "--",
  "nix/deno",
  "karabiner-config",
  "scripts/fetch-deno-deps.ts",
])).split("\n");
const packages: {
  name: string;
  input?: string;
  source?: string;
  lockfile?: string;
  overlay: string;
}[] = [
  {
    name: "peek",
    input: "peek-nvim",
    overlay: "nix/overlays/neovim-plugins.nix",
  },
  { name: "zeno", input: "zeno-zsh", overlay: "nix/overlays/zeno.nix" },
  {
    name: "karabiner",
    source: "karabiner-config",
    lockfile: "karabiner-config/deno.lock",
    overlay: "nix/overlays/karabiner-config.nix",
  },
];
const updated: string[] = [];

for (const pkg of packages) {
  const inputChanged = pkg.input && previous
    ? previous.nodes[pkg.input]?.locked.narHash !==
      lock.nodes[pkg.input].locked.narHash
    : false;
  const compilerChanged = previous?.nodes.nixpkgs.locked.narHash !==
    lock.nodes.nixpkgs.locked.narHash;
  if (
    base !== "--all" && !inputChanged && !compilerChanged &&
    !changed.some((path) =>
      path.startsWith(`nix/deno/${pkg.name}/`) ||
      (pkg.source && path.startsWith(`${pkg.source}/`)) ||
      path === "scripts/fetch-deno-deps.ts"
    )
  ) continue;
  const values = JSON.parse(
    await checked(run, "nix", [
      "eval",
      "--impure",
      "--json",
      "--expr",
      `let f = builtins.getFlake ("path:" + toString ./.); in { source = ${
        pkg.input ? `f.inputs.${pkg.input}.outPath` : `toString ./${pkg.source}`
      }; deno = (builtins.getAttr builtins.currentSystem f.inputs.nixpkgs.legacyPackages).deno.outPath; }`,
    ]),
  );
  const temporary = await Deno.makeTempDir({ prefix: "deno-deps-update-" });
  try {
    const source = `${temporary}/source`;
    await checked(run, "cp", ["-R", values.source, source]);
    await checked(run, "chmod", ["-R", "u+w", source]);
    const manifest = `${root}/nix/deno/${pkg.name}/manifest.json`;
    const dependencyLock = `${root}/${
      pkg.lockfile ?? `nix/deno/${pkg.name}/deno.lock`
    }`;
    if (pkg.name === "peek" && inputChanged) {
      const build = await Deno.readTextFile(`${source}/scripts/build.js`);
      if (!build.includes("https://deno.land/x/emit@0.38.1/mod.ts")) {
        throw new Error(
          "Peek emitter changed; review the offline bundler before updating",
        );
      }
      const assets: Record<string, string> = {};
      for (
        const match of build.matchAll(
          /download\(\s*'([^']+)',\s*'public\/([^']+)'/g,
        )
      ) {
        assets[match[2]] = match[1];
      }
      const fontBase = build.match(/`(https:\/\/[^`]+)\$\{font\}`/);
      const fonts = [...build.matchAll(/'(KaTeX_[^']+\.woff2)'/g)];
      if (Object.keys(assets).length !== 3 || !fontBase || !fonts.length) {
        throw new Error(
          "Peek asset layout changed; review the manifest generator",
        );
      }
      for (const font of fonts) {
        assets[`fonts/${font[1]}`] = `${fontBase[1]}${font[1]}`;
      }
      assets["emit_bg.wasm"] = "https://deno.land/x/emit@0.38.1/emit_bg.wasm";
      const data = JSON.parse(await Deno.readTextFile(manifest));
      data.assets = assets;
      await Deno.writeTextFile(manifest, JSON.stringify(data, null, 2) + "\n");
    }
    if (!inputChanged) {
      await Deno.copyFile(dependencyLock, `${source}/deno.lock`);
    }
    const result = await new Deno.Command(`${values.deno}/bin/deno`, {
      cwd: source,
      args: [
        "run",
        "--no-config",
        "--no-lock",
        "--allow-all",
        `${root}/scripts/fetch-deno-deps.ts`,
        manifest,
        `${temporary}/deps`,
      ],
      env: {
        DENO_DIR: `${temporary}/cache`,
        DENO_DEPS_FROZEN: inputChanged ? "0" : "1",
      },
      stdout: "inherit",
      stderr: "inherit",
    }).output();
    if (!result.success) {
      throw new Error(`${pkg.name}: dependency fetch failed`);
    }
    const hash = await checked(run, "nix", [
      "hash",
      "path",
      `${temporary}/deps`,
    ]);
    const overlay = await Deno.readTextFile(pkg.overlay);
    const matches = [...overlay.matchAll(/denoDepsHash = "sha256-[^"]+";/g)];
    if (matches.length !== 1) {
      throw new Error(`${pkg.overlay}: expected one dependency hash`);
    }
    await Deno.copyFile(`${temporary}/deps/deno.lock`, dependencyLock);
    await Deno.writeTextFile(
      pkg.overlay,
      overlay.replace(matches[0][0], `denoDepsHash = "${hash}";`),
    );
    updated.push(pkg.name);
  } finally {
    await Deno.remove(temporary, { recursive: true });
  }
}
console.log(`changed=${updated.join(", ")}`);
