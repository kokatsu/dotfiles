import {
  baseSource,
  binaryFile,
  checked,
  detect,
  goModules,
  hexToSri,
  type Manifest,
  packages,
  parseManifest,
  replaceHashes,
  type Run,
  run,
  sri,
  version,
} from "./hash-update-lib.ts";

async function prefetch(
  url: string,
  unpack: boolean,
  runCommand: Run,
): Promise<string> {
  const hash = await checked(runCommand, "nix-prefetch-url", [
    ...(unpack ? ["--unpack"] : []),
    "--type",
    "sha256",
    url,
  ]);
  return sri(
    await checked(runCommand, "nix", [
      "hash",
      "convert",
      "--hash-algo",
      "sha256",
      "--to",
      "sri",
      hash,
    ]),
  );
}

export async function binaryHashes(
  entry: Manifest[string],
  runCommand: Run = run,
): Promise<Record<string, string>> {
  const hashes: Record<string, string> = {};
  const urls = Object.values(entry.targets).map((target) => target.url);
  let publisher: Record<string, { checksum?: unknown }> = {};
  let sums = "";
  if (entry.hashSource === "manifest") {
    const manifestUrl = new URL("../manifest.json", urls[0]).href;
    if (
      !urls.every((url) =>
        new URL("../manifest.json", url).href === manifestUrl
      )
    ) throw new Error("inconsistent publisher manifest URLs");
    publisher =
      JSON.parse(await checked(runCommand, "curl", ["-fsSL", manifestUrl]))
        .platforms;
  } else if (entry.hashSource === "sha256sums") {
    const sumsUrl = new URL("codex-package_SHA256SUMS", urls[0]).href;
    if (
      !urls.every((url) =>
        new URL("codex-package_SHA256SUMS", url).href === sumsUrl
      )
    ) throw new Error("inconsistent checksum URLs");
    sums = await checked(runCommand, "curl", ["-fsSL", sumsUrl]);
  }
  for (const [system, target] of Object.entries(entry.targets)) {
    if (entry.hashSource === "prefetch") {
      hashes[system] = await prefetch(target.url, false, runCommand);
    } else if (entry.hashSource === "manifest") {
      const platform = new URL(target.url).pathname.split("/").at(-2)!;
      hashes[system] = hexToSri(publisher?.[platform]?.checksum);
    } else {
      const filename = new URL(target.url).pathname.split("/").at(-1)!;
      const matches = sums.split("\n").map((line) => line.trim().split(/\s+/))
        .filter((parts) => parts[1] === filename);
      if (matches.length !== 1) {
        throw new Error(
          `${filename}: expected one checksum, got ${matches.length}`,
        );
      }
      hashes[system] = hexToSri(matches[0][0]);
    }
  }
  return hashes;
}

async function manifest(runCommand: Run): Promise<Manifest> {
  return parseManifest(
    await checked(runCommand, "nix", [
      "eval",
      "--json",
      ".#lib.hashUpdateManifest",
    ]),
    await Deno.readTextFile(binaryFile),
  );
}

// 一時的な取得失敗で無関係な PR のハッシュ更新を止めないよう、取得失敗は警告に
// とどめ、不一致は全件を報告してから失敗させる
export async function verify(runCommand: Run = run): Promise<void> {
  let mismatches = 0;
  for (const [name, entry] of Object.entries(await manifest(runCommand))) {
    for (const [system, target] of Object.entries(entry.targets)) {
      let actual: string;
      try {
        actual = await prefetch(target.url, false, runCommand);
      } catch {
        console.log(
          `::warning::${name} (${system}): could not fetch ${target.url}`,
        );
        continue;
      }
      if (actual !== target.hash) {
        console.log(
          `::error::${name} (${system}): hash mismatch: expected ${target.hash}, got ${actual}`,
        );
        mismatches++;
      } else {
        console.error(`${name} (${system}): OK`);
      }
    }
  }
  if (mismatches > 0) throw new Error(`${mismatches} hash mismatch(es) found`);
}

export async function vendorHash(
  file: string,
  name: string,
  source: string,
  runCommand: Run = run,
): Promise<string> {
  const original = await Deno.readTextFile(file);
  const fake = `sha256-${"A".repeat(43)}=`;
  try {
    await Deno.writeTextFile(
      file,
      replaceHashes(source, name, { vendorHash: fake }),
    );
    const result = await runCommand("nix", [
      "build",
      "--no-link",
      "--impure",
      "--expr",
      `
      let pkgs = import (builtins.getFlake (toString ./.)).inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ (import ./${file}).${name} ];
      }; in pkgs.${name}`,
    ]);
    const matches = [
      ...result.stderr.matchAll(/got:\s+(sha256-[A-Za-z0-9+/]{43}=)/g),
    ];
    if (result.code === 0 || matches.length !== 1) {
      throw new Error(
        `${name}: expected one vendor hash mismatch\n${result.stderr}`,
      );
    }
    return sri(matches[0][1]);
  } finally {
    await Deno.writeTextFile(file, original);
  }
}

export async function update(
  base: string,
  runCommand: Run = run,
  temporaryRoot?: string,
): Promise<string> {
  const outputs = await detect(base, runCommand);
  const changes = new Map<string, string>();
  const read = async (file: string) =>
    changes.get(file) ?? await Deno.readTextFile(file);
  const change = async (
    file: string,
    name: string,
    values: Record<string, string>,
  ) => {
    changes.set(file, replaceHashes(await read(file), name, values));
  };
  const prefetchPackages: string[] = [];
  const binaryManifest = await manifest(runCommand);
  const previousBinary = await baseSource(base, binaryFile, runCommand);
  for (const [name, entry] of Object.entries(binaryManifest)) {
    if (version(previousBinary, name, true) === entry.version) continue;
    await change(binaryFile, name, await binaryHashes(entry, runCommand));
    if (entry.hashSource === "prefetch") {
      prefetchPackages.push(`${name} ${entry.version}`);
    }
  }

  const temporary = await Deno.makeTempDir({
    prefix: "dotfiles-hashes-",
    dir: temporaryRoot,
  });
  const root = Deno.cwd();
  try {
    for (const pkg of packages) {
      if (
        pkg.kind === "binary" ||
        !outputs[`has_${pkg.name.replaceAll("-", "_")}`]
      ) continue;
      const current = version(await read(pkg.file), pkg.name)!;
      const directory = `${temporary}/${pkg.name}`;
      if (pkg.kind === "npm") {
        const lockDir = `nix/npm-locks/${pkg.name}`;
        const packageFile = `${lockDir}/package.json`;
        const data = JSON.parse(await read(packageFile));
        if (typeof data.dependencies?.[pkg.dependency] !== "string") {
          throw new Error(
            `${packageFile}: missing dependency ${pkg.dependency}`,
          );
        }
        data.dependencies[pkg.dependency] = current;
        const json = JSON.stringify(data, null, 2) + "\n";
        await Deno.mkdir(directory);
        await Deno.writeTextFile(`${directory}/package.json`, json);
        await checked(runCommand, "npm", [
          "install",
          "--package-lock-only",
          "--ignore-scripts",
          ...pkg.npmFlags,
        ], directory);
        const hash = sri(
          await checked(runCommand, "nix", [
            "run",
            "--inputs-from",
            root,
            "nixpkgs#prefetch-npm-deps",
            "--",
            `${directory}/package-lock.json`,
          ]),
        );
        await change(pkg.file, pkg.name, { npmDepsHash: hash });
        changes.set(packageFile, json);
        changes.set(
          `${lockDir}/package-lock.json`,
          await Deno.readTextFile(`${directory}/package-lock.json`),
        );
      } else {
        const hash = await prefetch(
          `https://github.com/${pkg.repository}/archive/refs/tags/v${current}.tar.gz`,
          true,
          runCommand,
        );
        await change(pkg.file, pkg.name, { hash });
        if (pkg.kind === "source-npm") {
          await checked(runCommand, "git", [
            "clone",
            "--depth",
            "1",
            "--branch",
            `v${current}`,
            `https://github.com/${pkg.repository}.git`,
            directory,
          ]);
          await checked(runCommand, "npm", [
            "install",
            "--package-lock-only",
            "--ignore-scripts",
          ], directory);
          const npmDepsHash = sri(
            await checked(runCommand, "nix", [
              "run",
              "--inputs-from",
              root,
              "nixpkgs#prefetch-npm-deps",
              "--",
              `${directory}/package-lock.json`,
            ]),
          );
          await change(pkg.file, pkg.name, { npmDepsHash });
        } else {
          await change(pkg.file, pkg.name, {
            vendorHash: await vendorHash(
              pkg.file,
              pkg.name,
              await read(pkg.file),
              runCommand,
            ),
          });
        }
      }
    }
    for (const name of goModules) {
      if (!outputs[`has_${name.replaceAll("-", "_")}`]) continue;
      const file = `nix/overlays/${name}.nix`;
      await change(file, name, {
        vendorHash: await vendorHash(file, name, await read(file), runCommand),
      });
    }
    // Validate every staged result before writing any permanent changes.
    for (const [file, content] of changes) {
      if (file.endsWith(".nix")) {
        const path = `${temporary}/validate.nix`;
        await Deno.writeTextFile(path, content);
        await checked(runCommand, "nix-instantiate", ["--parse", path]);
      } else {
        JSON.parse(content);
      }
    }
    for (const [file, content] of changes) {
      await Deno.writeTextFile(file, content);
    }
    return prefetchPackages.join(", ");
  } finally {
    await Deno.remove(temporary, { recursive: true });
  }
}

if (import.meta.main) {
  try {
    const [command, base] = Deno.args;
    if (command === "verify" && !base) await verify();
    else if (command === "update" && base) {
      console.log(`changed=${await update(base)}`);
    } else if (command === "detect" && base) {
      for (const [key, value] of Object.entries(await detect(base))) {
        console.log(`${key}=${value}`);
      }
    } else {throw new Error(
        "usage: update-hashes.ts detect|update <base-ref> | verify",
      );}
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
