#!/usr/bin/env -S deno run --allow-read --allow-write
/**
 * Render Mermaid diagrams using beautiful-mermaid.
 *
 * Usage:
 *   deno run --allow-read --allow-write mermaid-render.ts <input.mmd> [options]
 *   cat input.mmd | deno run --allow-read --allow-write mermaid-render.ts - [options]
 *
 * Options:
 *   --ascii          ASCII output to stdout (default)
 *   --svg            SVG output (writes to <input>.svg or stdout with -)
 *   --out <file>     Output file path (overrides default)
 *   --theme <name>   Theme name (e.g. tokyo-night, dracula, nord, catppuccin-mocha)
 *   --use-ascii      Use ASCII chars instead of Unicode box-drawing
 *   --index <n>      Select nth mermaid block from markdown (0-based, default: 0)
 *   --list-themes    List available themes
 *
 * Markdown support:
 *   .md files are auto-detected. Mermaid code blocks (```mermaid) are extracted.
 *   If multiple blocks exist, use --index to select one, or omit to render the first.
 */

import {
  renderMermaid,
  renderMermaidAscii,
  THEMES,
} from 'npm:beautiful-mermaid';

function usage(): never {
  console.log(`Usage: mermaid-render.ts <input.mmd|input.md> [options]
       cat input.mmd | mermaid-render.ts - [options]

Options:
  --ascii          ASCII/Unicode art to stdout (default)
  --svg            SVG output (writes to <input>.svg or stdout with -)
  --out <file>     Output file path
  --theme <name>   Built-in theme name
  --use-ascii      Use plain ASCII instead of Unicode box-drawing
  --index <n>      Select nth mermaid block from markdown (0-based, default: 0)
  --list-themes    List available themes

Markdown (.md) files are auto-detected and mermaid code blocks are extracted.`);
  Deno.exit(0);
}

function listThemes(): never {
  console.log('Available themes:');
  for (const name of Object.keys(THEMES)) {
    console.log(`  ${name}`);
  }
  Deno.exit(0);
}

interface Options {
  input: string;
  fromStdin: boolean;
  mode: 'ascii' | 'svg';
  out?: string;
  theme?: string;
  useAscii: boolean;
  index: number;
}

function parseArgs(args: string[]): Options {
  const opts: Options = {
    input: '',
    fromStdin: false,
    mode: 'ascii',
    useAscii: false,
    index: 0,
  };

  let i = 0;
  while (i < args.length) {
    const arg = args[i];
    switch (arg) {
      case '--help':
      case '-h':
        usage();
        break;
      case '--list-themes':
        listThemes();
        break;
      case '--ascii':
        opts.mode = 'ascii';
        break;
      case '--svg':
        opts.mode = 'svg';
        break;
      case '--use-ascii':
        opts.useAscii = true;
        break;
      case '--out':
      case '-o':
        opts.out = args[++i];
        break;
      case '--theme':
      case '-t':
        opts.theme = args[++i];
        break;
      case '--index':
      case '-n':
        opts.index = parseInt(args[++i], 10);
        break;
      default:
        if (arg.startsWith('-') && arg !== '-') {
          console.error(`Unknown option: ${arg}`);
          Deno.exit(1);
        }
        if (arg === '-') {
          opts.fromStdin = true;
        } else {
          opts.input = arg;
        }
    }
    i++;
  }

  if (!opts.input && !opts.fromStdin) {
    usage();
  }

  return opts;
}

function extractMermaidBlocks(markdown: string): string[] {
  return [...markdown.matchAll(/```mermaid\s*\n([\s\S]*?)```/g)].map((m) =>
    m[1].trim(),
  );
}

function isMarkdown(filename: string): boolean {
  return /\.md$/i.test(filename);
}

async function readInput(opts: Options): Promise<string> {
  let raw: string;
  if (opts.fromStdin) {
    raw = await new Response(Deno.stdin.readable).text();
  } else {
    raw = await Deno.readTextFile(opts.input);
  }
  raw = raw.trim();

  const shouldExtract = opts.fromStdin
    ? raw.includes('```mermaid')
    : isMarkdown(opts.input);

  if (!shouldExtract) return raw;

  const blocks = extractMermaidBlocks(raw);
  if (blocks.length === 0) {
    console.error('No ```mermaid blocks found.');
    Deno.exit(1);
  }
  if (opts.index >= blocks.length) {
    console.error(
      `Index ${opts.index} out of range. Found ${blocks.length} mermaid block(s).`,
    );
    Deno.exit(1);
  }
  if (blocks.length > 1) {
    console.error(
      `Found ${blocks.length} mermaid blocks. Rendering block ${opts.index}. Use --index to select another.`,
    );
  }
  return blocks[opts.index];
}

async function main() {
  const opts = parseArgs([...Deno.args]);
  const text = await readInput(opts);

  if (opts.mode === 'ascii') {
    const result = renderMermaidAscii(text, {
      useAscii: opts.useAscii,
    });
    if (opts.out) {
      await Deno.writeTextFile(opts.out, result);
      console.error(`Written to ${opts.out}`);
    } else {
      console.log(result);
    }
  } else {
    const themeColors = opts.theme ? THEMES[opts.theme] : undefined;
    if (opts.theme && !themeColors) {
      console.error(
        `Unknown theme: ${opts.theme}. Use --list-themes to see available themes.`,
      );
      Deno.exit(1);
    }

    const svg = await renderMermaid(text, themeColors ?? {});
    const outPath =
      opts.out ??
      (opts.fromStdin ? undefined : opts.input.replace(/\.[^.]+$/, '.svg'));

    if (outPath) {
      await Deno.writeTextFile(outPath, svg);
      console.error(`Written to ${outPath}`);
    } else {
      console.log(svg);
    }
  }
}

main();
