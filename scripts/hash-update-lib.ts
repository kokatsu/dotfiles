export const binaryFile = "nix/overlays/binary-releases.nix";

type Package =
  & {
    name: string;
    file: string;
  }
  & (
    | { kind: "binary" }
    | { kind: "npm"; dependency: string; npmFlags: string[] }
    | { kind: "source-npm" | "source-go"; repository: string }
  );

export const packages: Package[] = [
  {
    name: "cssmodules-language-server",
    file: "nix/overlays/source-builds.nix",
    kind: "source-npm",
    repository: "antonk52/cssmodules-language-server",
  },
  {
    name: "vite-plus",
    file: "nix/overlays/npm-packages.nix",
    kind: "npm",
    dependency: "vite-plus",
    npmFlags: ["--legacy-peer-deps"],
  },
  {
    name: "textlint-rule-preset-ai-writing",
    file: "nix/overlays/npm-packages.nix",
    kind: "npm",
    dependency: "@textlint-ja/textlint-rule-preset-ai-writing",
    npmFlags: [],
  },
  { name: "codex", file: binaryFile, kind: "binary" },
  {
    name: "x-api-playground",
    file: "nix/overlays/source-builds.nix",
    kind: "source-go",
    repository: "xdevplatform/playground",
  },
  { name: "claude-code", file: binaryFile, kind: "binary" },
];

// Go modules under tools/ whose nix/overlays/<name>.nix vendorHash follows go.sum
export const goModules = ["agent-guard", "codex-auto-title"];

function escape(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function one(matches: RegExpMatchArray[], label: string): RegExpMatchArray {
  if (matches.length !== 1) {
    throw new Error(`${label}: expected one match, got ${matches.length}`);
  }
  return matches[0];
}

// Overlay attributes use two spaces; nested attributes use four or more.
// Refuse ambiguous sections instead of editing a neighbouring package.
export function section(
  source: string,
  name: string,
  optional = false,
): string | undefined {
  const starts = [
    ...source.matchAll(new RegExp(`^ {2}${escape(name)} = .+$`, "gm")),
  ];
  if (optional && starts.length === 0) return undefined;
  const start = one(starts, `${name} section`).index!;
  const end = source.slice(start).search(/^ {2}};$/m);
  if (end < 0) throw new Error(`${name}: missing section end`);
  const body = source.slice(start, start + end + 4);
  if (/\n {2}[\w-]+ = /.test(body)) {
    throw new Error(`${name}: overlapping sections`);
  }
  return body;
}

export function version(
  source: string,
  name: string,
  optional = false,
): string | undefined {
  const body = section(source, name, optional);
  if (body === undefined) return undefined;
  const value = one(
    [...body.matchAll(/^\s+version = "([^"\n]*)";$/gm)],
    `${name} version`,
  )[1];
  if (!/^[0-9A-Za-z.+_-]+$/.test(value)) {
    throw new Error(`${name}: invalid version ${value}`);
  }
  return value;
}

export function sri(value: unknown): string {
  if (typeof value !== "string" || !/^sha256-[A-Za-z0-9+/]{43}=$/.test(value)) {
    throw new Error(`invalid SHA256 SRI: ${value}`);
  }
  return value;
}

export function hexToSri(hex: unknown): string {
  if (typeof hex !== "string" || !/^[0-9a-fA-F]{64}$/.test(hex)) {
    throw new Error("invalid SHA256 checksum");
  }
  return `sha256-${
    btoa(String.fromCharCode(...hex.match(/../g)!.map((v) => parseInt(v, 16))))
  }`;
}

export function replaceHashes(
  source: string,
  name: string,
  values: Record<string, string>,
): string {
  const body = section(source, name)!;
  let updated = body;
  for (const [field, value] of Object.entries(values)) {
    sri(value);
    const key = field.includes("-") ? `"${escape(field)}"` : escape(field);
    const pattern = new RegExp(`^(\\s+${key} = ")([^"\\n]*)(";)$`, "gm");
    // Binary platformMap repeats the keys, so restrict platform edits to hashes.
    const target = field.includes("-")
      ? one(
        [...updated.matchAll(/^ {4}hashes = \{\n[\s\S]*?^ {4}};/gm)],
        `${name} hashes`,
      )[0]
      : updated;
    const match = one([...target.matchAll(pattern)], `${name}.${field}`);
    sri(match[2]);
    const changed = target.replace(
      pattern,
      (_all, prefix, _old, suffix) => `${prefix}${value}${suffix}`,
    );
    updated = updated.replace(target, () => changed);
  }
  return source.replace(body, () => updated);
}

export type Manifest = Record<string, {
  version: string;
  hashSource: "prefetch" | "manifest" | "sha256sums";
  targets: Record<string, { url: string; hash: string }>;
}>;

export function parseManifest(input: string, source: string): Manifest {
  const manifest = JSON.parse(input) as Manifest;
  const names = [...source.matchAll(/^ {2}([\w-]+) = mkBinaryRelease\b/gm)].map(
    (
      m,
    ) => m[1],
  ).sort();
  if (
    names.length === 0 ||
    JSON.stringify(names) !== JSON.stringify(Object.keys(manifest).sort())
  ) {
    throw new Error("manifest packages differ from binary overlay sections");
  }
  for (const [name, entry] of Object.entries(manifest)) {
    if (version(source, name) !== entry.version) {
      throw new Error(`${name}: manifest version mismatch`);
    }
    if (!["prefetch", "manifest", "sha256sums"].includes(entry.hashSource)) {
      throw new Error(`${name}: unsupported hash source`);
    }
    const body = section(source, name)!;
    const hashes = one(
      [...body.matchAll(/^ {4}hashes = \{\n([\s\S]*?)^ {4}};/gm)],
      `${name} hashes`,
    )[1];
    const systems = [...hashes.matchAll(/^\s+"([\w-]+)" = /gm)].map((m) => m[1])
      .sort();
    if (
      !systems.length ||
      JSON.stringify(systems) !==
        JSON.stringify(Object.keys(entry.targets).sort())
    ) {
      throw new Error(`${name}: manifest platforms differ from overlay hashes`);
    }
    for (const target of Object.values(entry.targets)) {
      sri(target.hash);
      if (new URL(target.url).protocol !== "https:") {
        throw new Error(`${name}: invalid artifact URL`);
      }
    }
    if (
      replaceHashes(
        source,
        name,
        Object.fromEntries(
          Object.entries(entry.targets).map((
            [system, target],
          ) => [system, target.hash]),
        ),
      ) !== source
    ) {
      throw new Error(`${name}: manifest hash mismatch`);
    }
  }
  return manifest;
}

export type Result = { code: number; stdout: string; stderr: string };
export type Run = (
  command: string,
  args: string[],
  cwd?: string,
) => Promise<Result>;
export const run: Run = async (command, args, cwd) => {
  const output = await new Deno.Command(command, {
    args,
    cwd,
    stdout: "piped",
    stderr: "piped",
  }).output();
  return {
    code: output.code,
    stdout: new TextDecoder().decode(output.stdout),
    stderr: new TextDecoder().decode(output.stderr),
  };
};

export async function checked(
  run: Run,
  command: string,
  args: string[],
  cwd?: string,
): Promise<string> {
  const result = await run(command, args, cwd);
  if (result.code !== 0) {
    throw new Error(
      `${command} ${args.join(" ")}: exit ${result.code}\n${result.stderr}`,
    );
  }
  return result.stdout.trim();
}

export async function baseSource(
  base: string,
  file: string,
  runCommand: Run = run,
): Promise<string> {
  // Validate the ref separately: an invalid ref must not look like a new file.
  const commit = await checked(runCommand, "git", [
    "rev-parse",
    "--verify",
    "--end-of-options",
    `${base}^{commit}`,
  ]);
  const exists = await checked(runCommand, "git", [
    "ls-tree",
    "--name-only",
    commit,
    "--",
    file,
  ]);
  return exists
    ? await checked(runCommand, "git", ["show", `${commit}:${file}`])
    : "";
}

export async function detect(
  base: string,
  runCommand: Run = run,
): Promise<Record<string, string>> {
  const output: Record<string, string> = {};
  const changed: string[] = [];
  for (const pkg of packages) {
    const current = version(await Deno.readTextFile(pkg.file), pkg.name)!;
    const previous = version(
      await baseSource(base, pkg.file, runCommand),
      pkg.name,
      true,
    );
    if (current === previous) continue;
    const key = pkg.name.replaceAll("-", "_");
    output[`has_${key}`] = "true";
    output[`version_${key}`] = current;
    changed.push(`${pkg.name} ${current}`);
  }
  const paths = (await checked(runCommand, "git", [
    "diff",
    "--name-only",
    base,
    "--",
    "karabiner-config",
    "flake.nix",
    ...goModules.map((name) => `tools/${name}/go.sum`),
  ])).split("\n");
  if (paths.some((p) => /^karabiner-config\/deno\.(json|lock)$/.test(p))) {
    output.has_karabinerts_deno_lock = "true";
  }
  if (paths.includes("flake.nix")) output.has_flake_nix = "true";
  for (const name of goModules) {
    if (!paths.includes(`tools/${name}/go.sum`)) continue;
    output[`has_${name.replaceAll("-", "_")}`] = "true";
    changed.push(name);
  }
  output.packages = changed.join(", ");
  return output;
}
