import {
  binaryFile,
  checked,
  goModules,
  hexToSri,
  type Manifest,
  packages,
  parseManifest,
  replaceHashes,
  type Run,
  run,
  section,
  sri,
  version,
} from "./hash-update-lib.ts";
import { binaryHashes, update, vendorHash, verify } from "./update-hashes.ts";

const root = Deno.cwd();
const temporary = Deno.args[0];
if (!temporary) {
  throw new Error("usage: test-hash-updates.ts -- <temporary-dir>");
}
const oldHash = `sha256-${"A".repeat(43)}=`;
const newHash = hexToSri("11".repeat(32));

function equal(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
async function rejects(fn: () => unknown, message: string): Promise<void> {
  try {
    await fn();
  } catch (error) {
    if (String(error).includes(message)) return;
    throw error;
  }
  throw new Error(`expected failure containing ${message}`);
}

const sample = `{
  demo = mkBinaryRelease rec {
    version = "1.0";
    hashes = {
      "aarch64-linux" = "${oldHash}";
    };
    platformMap = { "aarch64-linux" = "linux-arm64"; };
  };
}
`;
const entry: Manifest[string] = {
  version: "1.0",
  hashSource: "prefetch",
  targets: {
    "aarch64-linux": {
      url: "https://example.test/1.0/linux-arm64/tool",
      hash: oldHash,
    },
  },
};

Deno.test("replacement preserves other packages, verifies count, and is idempotent", async () => {
  const source = sample + sample.replaceAll("demo", "other");
  const result = replaceHashes(source, "demo", { "aarch64-linux": newHash });
  equal(result, source.replace(oldHash, newHash));
  equal(replaceHashes(result, "demo", { "aarch64-linux": newHash }), result);
  await rejects(
    () => replaceHashes(source, "absent", { hash: newHash }),
    "expected one match, got 0",
  );
  await rejects(
    () => replaceHashes(sample + sample, "demo", { hash: newHash }),
    "expected one match, got 2",
  );
  await rejects(
    () => replaceHashes(sample, "demo", { "x86_64-linux": newHash }),
    "expected one match, got 0",
  );
  await rejects(
    () =>
      replaceHashes(
        sample.replace(
          `      "aarch64-linux" = "${oldHash}";`,
          `      "aarch64-linux" = "${oldHash}";\n      "aarch64-linux" = "${oldHash}";`,
        ),
        "demo",
        { "aarch64-linux": newHash },
      ),
    "expected one match, got 2",
  );
  await rejects(
    () =>
      version(
        sample.replace('version = "1.0";', 'version = "$(evil)";'),
        "demo",
      ),
    "invalid version",
  );
  await rejects(() => sri("sha256-invalid"), "invalid SHA256");
});

Deno.test("manifest rejects missing packages, platforms, stale versions and hashes", async () => {
  equal(parseManifest(JSON.stringify({ demo: entry }), sample), {
    demo: entry,
  });
  await rejects(() => parseManifest("{}", sample), "packages differ");
  await rejects(
    () =>
      parseManifest(
        JSON.stringify({ demo: { ...entry, targets: {} } }),
        sample,
      ),
    "platforms differ",
  );
  await rejects(
    () =>
      parseManifest(
        JSON.stringify({ demo: { ...entry, version: "2" } }),
        sample,
      ),
    "version mismatch",
  );
  await rejects(
    () =>
      parseManifest(
        JSON.stringify({
          demo: {
            ...entry,
            targets: {
              "aarch64-linux": {
                ...entry.targets["aarch64-linux"],
                hash: newHash,
              },
            },
          },
        }),
        sample,
      ),
    "hash mismatch",
  );
});

Deno.test("publisher checksums use manifest URLs and require one valid hash per target", async () => {
  const calls: string[][] = [];
  const mock: Run = (command, args) => {
    calls.push([command, ...args]);
    return Promise.resolve({
      code: 0,
      stderr: "",
      stdout: JSON.stringify({
        platforms: { "linux-arm64": { checksum: "11".repeat(32) } },
      }),
    });
  };
  equal(await binaryHashes({ ...entry, hashSource: "manifest" }, mock), {
    "aarch64-linux": newHash,
  });
  equal(calls, [["curl", "-fsSL", "https://example.test/1.0/manifest.json"]]);
  const sumsEntry: Manifest[string] = {
    ...entry,
    hashSource: "sha256sums",
    targets: {
      linux: {
        url: "https://example.test/rust-v1/codex-package-linux.tar.gz",
        hash: oldHash,
      },
    },
  };
  const sums: Run = () =>
    Promise.resolve({
      code: 0,
      stderr: "",
      stdout: `${"11".repeat(32)}  codex-package-linux.tar.gz\n${
        "22".repeat(32)
      }  unrelated.tar.gz`,
    });
  equal(await binaryHashes(sumsEntry, sums), { linux: newHash });
  await rejects(
    () =>
      binaryHashes(
        sumsEntry,
        async (...args) => ({
          ...await sums(...args),
          stdout: ((await sums(...args)).stdout + "\n").repeat(2),
        }),
      ),
    "expected one checksum",
  );
  await rejects(
    () =>
      binaryHashes(
        { ...entry, hashSource: "manifest" },
        () =>
          Promise.resolve({ code: 0, stderr: "", stdout: '{"platforms":{}}' }),
      ),
    "invalid SHA256",
  );
  await rejects(
    () =>
      binaryHashes(
        entry,
        () => Promise.resolve({ code: 1, stderr: "offline", stdout: "" }),
      ),
    "offline",
  );
});

Deno.test("every real overlay target can be changed without touching its neighbours", async () => {
  const binary = await Deno.readTextFile(binaryFile);
  const names = [...binary.matchAll(/^ {2}([\w-]+) = mkBinaryRelease/gm)].map((
    m,
  ) => m[1]);
  equal(names.length, [...binary.matchAll(/mkBinaryRelease.*\{/g)].length);
  if (!names.length) throw new Error("no binary packages");
  for (const name of names) {
    version(binary, name);
    const body = section(binary, name)!;
    const systems = [...body.matchAll(/^ {6}"([\w-]+)" = "sha256-/gm)].map((
      m,
    ) => m[1]);
    equal(systems.length, 3);
    const result = replaceHashes(
      binary,
      name,
      Object.fromEntries(systems.map((s) => [s, newHash])),
    );
    equal(
      result,
      binary.replace(body, body.replace(/sha256-[A-Za-z0-9+/]{43}=/g, newHash)),
    );
    const path = `${temporary}/binary.nix`;
    await Deno.writeTextFile(path, result);
    await checked(run, "nix-instantiate", ["--parse", path]);
  }
  for (
    const file of [
      "nix/overlays/npm-packages.nix",
      "nix/overlays/source-builds.nix",
    ]
  ) {
    const source = await Deno.readTextFile(file);
    const discovered = [...source.matchAll(/^ {2}([\w-]+) = _final: prev:/gm)]
      .map((m) => m[1]).sort();
    equal(
      discovered,
      packages.filter((p) => p.file === file).map((p) => p.name).sort(),
    );
    for (const name of discovered) {
      version(source, name);
      const body = section(source, name)!;
      const fields = [
        ...body.matchAll(/^\s+(hash|npmDepsHash|vendorHash) = /gm),
      ].map((m) => m[1]);
      const result = replaceHashes(
        source,
        name,
        Object.fromEntries(fields.map((f) => [f, newHash])),
      );
      equal(
        result,
        source.replace(
          body,
          body.replace(/sha256-[A-Za-z0-9+/]{43}=/g, newHash),
        ),
      );
      const path = `${temporary}/source.nix`;
      await Deno.writeTextFile(path, result);
      await checked(run, "nix-instantiate", ["--parse", path]);
    }
  }
});

Deno.test("update stages npm locks and binary hashes, preserves unrelated files, and repeats cleanly", async () => {
  const directory = `${temporary}/repo`;
  await Deno.mkdir(`${directory}/nix/overlays`, { recursive: true });
  const files = new Set([
    ...packages.map((p) => p.file),
    ...goModules.map((name) => `nix/overlays/${name}.nix`),
  ]);
  for (const file of files) await Deno.copyFile(file, `${directory}/${file}`);
  for (const pkg of packages.filter((p) => p.kind === "npm")) {
    const lockDir = `nix/npm-locks/${pkg.name}`;
    await Deno.mkdir(`${directory}/${lockDir}`, { recursive: true });
    await Deno.copyFile(
      `${lockDir}/package.json`,
      `${directory}/${lockDir}/package.json`,
    );
  }
  for (const name of goModules) {
    await Deno.mkdir(`${directory}/tools/${name}`, { recursive: true });
    await Deno.writeTextFile(`${directory}/tools/${name}/go.sum`, "base\n");
  }
  try {
    Deno.chdir(directory);
    await checked(run, "git", ["init", "-q"]);
    await checked(run, "git", ["add", "."]);
    await checked(run, "git", [
      "-c",
      "user.name=test",
      "-c",
      "user.email=test@example.test",
      "commit",
      "-qm",
      "base",
    ]);
    const base = await checked(run, "git", ["rev-parse", "HEAD"]);
    const npmFile = "nix/overlays/npm-packages.nix";
    const npmSource = await Deno.readTextFile(npmFile);
    const originalSection = section(npmSource, "vite-plus")!;
    await Deno.writeTextFile(
      npmFile,
      npmSource.replace(
        originalSection,
        originalSection.replace(/version = "[^"]+"/, 'version = "9.9.9"'),
      ),
    );
    const binarySource = await Deno.readTextFile(binaryFile);
    const originalBinary = section(binarySource, "mise")!;
    await Deno.writeTextFile(
      binaryFile,
      binarySource.replace(
        originalBinary,
        originalBinary.replace(/version = "[^"]+"/, 'version = "9.9.9"'),
      ),
    );
    const calls: { command: string; args: string[]; cwd?: string }[] = [];
    const mock: Run = async (command, args, cwd) => {
      calls.push({ command, args, cwd });
      if (command === "git" && args[0] === "clone") {
        const clone = args.at(-1)!;
        await Deno.mkdir(clone);
        await Deno.writeTextFile(
          `${clone}/package.json`,
          '{"name":"cssmodules-language-server"}',
        );
        return { code: 0, stdout: "", stderr: "" };
      }
      if (command === "git" || command === "nix-instantiate") {
        return run(command, args, cwd);
      }
      let stdout = newHash;
      if (command === "nix" && args[0] === "eval") {
        const source = await Deno.readTextFile(binaryFile);
        const result: Manifest = {};
        for (
          const match of source.matchAll(/^ {2}([\w-]+) = mkBinaryRelease/gm)
        ) {
          const body = section(source, match[1])!;
          result[match[1]] = {
            version: version(source, match[1])!,
            hashSource: "prefetch",
            targets: Object.fromEntries(
              [...body.matchAll(/^ {6}"([\w-]+)" = "(sha256-[^"]+)"/gm)].map((
                m,
              ) => [m[1], {
                url: `https://example.test/${match[1]}/${m[1]}`,
                hash: m[2],
              }]),
            ),
          };
        }
        stdout = JSON.stringify(result);
      } else if (command === "npm") {
        const json = JSON.parse(await Deno.readTextFile(`${cwd}/package.json`));
        if (json.dependencies) {
          equal(Object.values(json.dependencies)[0], "9.9.9");
        }
        await Deno.writeTextFile(
          `${cwd}/package-lock.json`,
          '{"lockfileVersion":3}\n',
        );
        stdout = "";
      } else if (command === "nix" && args[0] === "build") {
        return {
          code: 1,
          stdout: "",
          stderr: `hash mismatch\n got: ${newHash}`,
        };
      }
      return { code: 0, stdout, stderr: "" };
    };
    equal(await update(base, mock, temporary), "mise 9.9.9");
    const updated = await Deno.readTextFile(npmFile);
    equal(
      updated.replace(section(updated, "vite-plus")!, ""),
      npmSource.replace(originalSection, ""),
    );
    equal(updated.includes(`npmDepsHash = "${newHash}"`), true);
    equal(
      await Deno.readTextFile("nix/npm-locks/vite-plus/package-lock.json"),
      '{"lockfileVersion":3}\n',
    );
    equal(calls.filter((c) => c.command === "npm").map((c) => c.args), [[
      "install",
      "--package-lock-only",
      "--ignore-scripts",
      "--legacy-peer-deps",
    ]]);
    equal(
      calls.find((c) => c.command === "nix" && c.args[0] === "run")!.args.slice(
        0,
        4,
      ),
      ["run", "--inputs-from", directory, "nixpkgs#prefetch-npm-deps"],
    );
    const diff = await checked(run, "git", ["diff"]);
    await update(base, mock, temporary);
    equal(await checked(run, "git", ["diff"]), diff);
    await rejects(
      () =>
        update(
          base,
          (command, args, cwd) =>
            command === "nix-prefetch-url"
              ? Promise.resolve({ code: 1, stdout: "", stderr: "offline" })
              : mock(command, args, cwd),
        ),
      "offline",
    );
    equal(await checked(run, "git", ["diff"]), diff);
    let fetches = 0;
    await rejects(
      () =>
        verify((command, args, cwd) =>
          command === "nix-prefetch-url" && fetches++ === 0
            ? Promise.resolve({ code: 1, stdout: "", stderr: "offline" })
            : mock(command, args, cwd)
        ),
      "hash mismatch(es) found",
    );
    equal(
      fetches,
      (await Deno.readTextFile(binaryFile)).match(/^ {6}"[\w-]+" = "sha256-/gm)!
        .length,
    );
    const vendorFile = "nix/overlays/agent-guard.nix";
    const vendorSource = await Deno.readTextFile(vendorFile);
    equal(
      await vendorHash(
        vendorFile,
        "agent-guard",
        vendorSource,
        () =>
          Promise.resolve({
            code: 1,
            stdout: "",
            stderr: `hash mismatch\n got: ${newHash}`,
          }),
      ),
      newHash,
    );
    equal(await Deno.readTextFile(vendorFile), vendorSource);
    for (
      const name of [
        "cssmodules-language-server",
        "textlint-rule-preset-ai-writing",
        "x-api-playground",
      ]
    ) {
      const pkg = packages.find((pkg) => pkg.name === name)!;
      const source = await Deno.readTextFile(pkg.file);
      const body = section(source, name)!;
      await Deno.writeTextFile(
        pkg.file,
        source.replace(
          body,
          body.replace(/version = "[^"]+"/, 'version = "9.9.9"'),
        ),
      );
    }
    for (const name of goModules) {
      await Deno.writeTextFile(`tools/${name}/go.sum`, "changed\n");
    }
    equal(await update(base, mock, temporary), "mise 9.9.9");
    const source = await Deno.readTextFile("nix/overlays/source-builds.nix");
    equal(
      section(source, "cssmodules-language-server")!.match(
        /sha256-[A-Za-z0-9+/]{43}=/g,
      ),
      [newHash, newHash],
    );
    equal(
      section(source, "x-api-playground")!.match(/sha256-[A-Za-z0-9+/]{43}=/g),
      [newHash, newHash],
    );
    for (const name of goModules) {
      equal(
        (await Deno.readTextFile(`nix/overlays/${name}.nix`)).includes(
          `vendorHash = "${newHash}"`,
        ),
        true,
      );
    }
    equal(
      calls.some((c) =>
        c.command === "npm" &&
        c.cwd?.endsWith("/textlint-rule-preset-ai-writing") &&
        !c.args.includes("--legacy-peer-deps")
      ),
      true,
    );
    equal(
      calls.find((c) => c.command === "git" && c.args[0] === "clone")!.args
        .slice(0, -1),
      [
        "clone",
        "--depth",
        "1",
        "--branch",
        "v9.9.9",
        "https://github.com/antonk52/cssmodules-language-server.git",
      ],
    );
    equal(
      calls.some((c) =>
        c.command === "nix-prefetch-url" && c.args.includes("--unpack") &&
        c.args.at(-1) ===
          "https://github.com/xdevplatform/playground/archive/refs/tags/v9.9.9.tar.gz"
      ),
      true,
    );
    const updatedVendor = await Deno.readTextFile(vendorFile);
    await rejects(
      () =>
        vendorHash(
          vendorFile,
          "agent-guard",
          updatedVendor,
          () =>
            Promise.resolve({ code: 1, stdout: "", stderr: "network failed" }),
        ),
      "expected one vendor hash mismatch",
    );
    equal(await Deno.readTextFile(vendorFile), updatedVendor);
  } finally {
    Deno.chdir(root);
  }
});
