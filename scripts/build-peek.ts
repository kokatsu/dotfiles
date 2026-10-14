interface ModuleMap {
  modules: Record<string, { path: string; mediaType: string }>;
  redirects: Record<string, string>;
}

const [dependencies] = Deno.args;
if (!dependencies) throw new Error("usage: build-peek.ts <dependencies>");
const map: ModuleMap = JSON.parse(
  await Deno.readTextFile(`${dependencies}/module-map.json`),
);
const emitterUrl = new URL("https://deno.land/x/emit@0.38.1/mod.ts");
const { bundle } = await import(emitterUrl.href);
const { compilerOptions, imports } = JSON.parse(
  await Deno.readTextFile("deno.json"),
);

async function load(specifier: string) {
  if (specifier.startsWith("file:")) {
    return {
      kind: "module",
      specifier,
      content: await Deno.readTextFile(new URL(specifier)),
    };
  }
  while (map.redirects[specifier]) specifier = map.redirects[specifier];
  const module = map.modules[specifier];
  if (!module) throw new Error(`Unfixed dependency: ${specifier}`);
  return {
    kind: "module",
    specifier,
    content: await Deno.readTextFile(`${dependencies}/${module.path}`),
    headers: {
      "content-type": module.mediaType.includes("TypeScript")
        ? "application/typescript"
        : "application/javascript",
    },
  };
}

for (
  const [input, output] of [
    ["app/src/main.ts", "public/main.bundle.js"],
    ["app/src/webview.ts", "public/webview.js"],
    ["client/src/script.ts", "public/script.bundle.js"],
  ]
) {
  const result = await bundle(input, {
    compilerOptions,
    importMap: { imports },
    load,
  });
  if (!result.code) throw new Error(`Empty bundle: ${input}`);
  await Deno.writeTextFile(output, result.code);
}

const css = await Deno.readTextFile("public/github-markdown.min.css");
await Deno.writeTextFile(
  "public/github-markdown.min.css",
  css.replace("@media (prefers-color-scheme:dark)", "[data-theme=dark]")
    .replace("@media (prefers-color-scheme:light)", "[data-theme=light]"),
);
const index = await Deno.readTextFile("public/index.html");
if (!index.includes("<title>")) throw new Error("Peek index has no title");
await Deno.writeTextFile(
  "public/index.html",
  index.replace(
    "  <title>",
    `  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🔍</text></svg>">\n  <title>`,
  ),
);
