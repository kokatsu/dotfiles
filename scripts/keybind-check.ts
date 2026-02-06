#!/usr/bin/env -S deno run --allow-read --allow-env --allow-run
/**
 * Keybinding conflict checker for WezTerm, Neovim, and Yazi.
 *
 * WezTerm intercepts keys at the terminal level before they reach Neovim/Yazi.
 * This script detects such conflicts and reports them.
 *
 * Usage:
 *   deno run --allow-read --allow-env --allow-run bin/keybind-check.ts [options]
 *
 * Options:
 *   --platform linux|darwin   Platform override (default: auto-detect)
 *   --json                    JSON output
 *   --verbose                 Show all keybindings (not just conflicts)
 */

import { parse as parseTOML } from 'jsr:@std/toml@1';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type Tool = 'wezterm' | 'neovim' | 'yazi';

interface Keybinding {
  canonical: string;
  rawKey: string;
  tool: Tool;
  context: string;
  description: string;
  sourceFile: string;
  isPassthrough: boolean;
}

type Severity = 'critical' | 'info';

interface Conflict {
  canonical: string;
  severity: Severity;
  label: string;
  bindings: Keybinding[];
}

interface Options {
  platform: 'linux' | 'darwin';
  json: boolean;
  verbose: boolean;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(args: string[]): Options {
  const opts: Options = {
    platform: Deno.build.os === 'darwin' ? 'darwin' : 'linux',
    json: false,
    verbose: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    switch (arg) {
      case '--platform':
        {
          const v = args[++i];
          if (v !== 'linux' && v !== 'darwin') {
            console.error(`Invalid platform: ${v}`);
            Deno.exit(1);
          }
          opts.platform = v;
        }
        break;
      case '--json':
        opts.json = true;
        break;
      case '--verbose':
        opts.verbose = true;
        break;
      case '--help':
      case '-h':
        console.log(`Usage: keybind-check.ts [options]
  --platform linux|darwin   Platform override (default: auto-detect)
  --json                    JSON output
  --verbose                 Show all keybindings (not just conflicts)`);
        Deno.exit(0);
        break;
      default:
        console.error(`Unknown option: ${arg}`);
        Deno.exit(1);
    }
  }

  return opts;
}

// ---------------------------------------------------------------------------
// Dotfiles root detection
// ---------------------------------------------------------------------------

function findDotfilesRoot(): string {
  // Walk up from the script location or CWD
  const candidates = [
    // If run from the repo
    Deno.cwd(),
    // If the script is inside bin/
    new URL('.', import.meta.url).pathname.replace(/\/bin\/?$/, ''),
  ];

  for (const dir of candidates) {
    try {
      Deno.statSync(`${dir}/flake.nix`);
      return dir;
    } catch {
      // continue
    }
  }

  console.error('Could not find dotfiles root (flake.nix not found).');
  Deno.exit(1);
}

// ---------------------------------------------------------------------------
// Key normalisation
// ---------------------------------------------------------------------------

/** Modifier sort order for canonical form. */
const MOD_ORDER = ['ctrl', 'alt', 'shift', 'super'] as const;

/** Normalise a key binding string to `<sorted-mods>+<lowercase key>`. */
function normalizeKey(mods: string[], key: string): string {
  const sortedMods = [...new Set(mods)]
    .map((m) => m.toLowerCase())
    .sort((a, b) => {
      const ai = MOD_ORDER.indexOf(a as (typeof MOD_ORDER)[number]);
      const bi = MOD_ORDER.indexOf(b as (typeof MOD_ORDER)[number]);
      return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
    });

  const lowerKey = key.toLowerCase();
  return sortedMods.length > 0
    ? `${sortedMods.join('+')}+${lowerKey}`
    : lowerKey;
}

// -- WezTerm helpers -------------------------------------------------------

const WEZTERM_KEY_MAP: Record<string, string> = {
  leftarrow: 'left',
  rightarrow: 'right',
  uparrow: 'up',
  downarrow: 'down',
  enter: 'enter',
  escape: 'escape',
  backspace: 'backspace',
  tab: 'tab',
};

function normalizeWeztermKey(
  rawKey: string,
  rawMods: string,
  platform: 'linux' | 'darwin',
): { canonical: string; mods: string[] } | null {
  // Resolve PRIMARY / SECONDARY per platform
  const modsMap: Record<string, string> =
    platform === 'darwin'
      ? { PRIMARY: 'CTRL', SECONDARY: 'ALT' }
      : { PRIMARY: 'CTRL', SECONDARY: 'ALT' };

  let modsStr = rawMods;
  for (const [placeholder, actual] of Object.entries(modsMap)) {
    modsStr = modsStr.replaceAll(placeholder, actual);
  }

  const modParts = modsStr
    .split('|')
    .map((m) => m.trim())
    .filter((m) => m !== '' && m !== 'NONE');

  // Uppercase single-char key implies Shift
  const hasShiftImplied =
    rawKey.length === 1 &&
    rawKey === rawKey.toUpperCase() &&
    rawKey !== rawKey.toLowerCase();

  const mods = modParts.map((m) => m.toLowerCase());
  let key = rawKey;

  if (hasShiftImplied && !mods.includes('shift')) {
    mods.push('shift');
  }

  const mapped = WEZTERM_KEY_MAP[key.toLowerCase()];
  if (mapped) key = mapped;

  return { canonical: normalizeKey(mods, key), mods };
}

// -- Neovim helpers --------------------------------------------------------

const NVIM_MOD_MAP: Record<string, string> = {
  C: 'ctrl',
  M: 'alt',
  A: 'alt',
  S: 'shift',
  D: 'super',
};

const NVIM_KEY_MAP: Record<string, string> = {
  cr: 'enter',
  return: 'enter',
  enter: 'enter',
  esc: 'escape',
  bs: 'backspace',
  tab: 'tab',
  space: 'space',
  lt: '<',
  bar: '|',
  bslash: '\\',
  up: 'up',
  down: 'down',
  left: 'left',
  right: 'right',
  f1: 'f1',
  f2: 'f2',
  f3: 'f3',
  f4: 'f4',
  f5: 'f5',
  f6: 'f6',
  f7: 'f7',
  f8: 'f8',
  f9: 'f9',
  f10: 'f10',
  f11: 'f11',
  f12: 'f12',
};

/**
 * Parse a Neovim lhs string. Returns null for multi-key sequences
 * (which cannot conflict with WezTerm single-key captures).
 */
function parseNvimLhs(
  lhs: string,
): { canonical: string; isSequence: boolean } | null {
  // Match <mod-key> patterns: <C-h>, <M-l>, <C-S-x>, etc.
  const bracketRe = /^<([^>]+)>$/;
  const m = lhs.match(bracketRe);

  if (m) {
    const inner = m[1];
    const parts = inner.split('-');
    const keyPart = parts[parts.length - 1];
    const modParts = parts.slice(0, -1);

    const mods: string[] = [];
    for (const mp of modParts) {
      const mapped = NVIM_MOD_MAP[mp.toUpperCase()];
      if (mapped) mods.push(mapped);
    }

    const mappedKey = NVIM_KEY_MAP[keyPart.toLowerCase()] ?? keyPart;
    return { canonical: normalizeKey(mods, mappedKey), isSequence: false };
  }

  // Single printable char (no angle brackets)
  if (lhs.length === 1) {
    return { canonical: normalizeKey([], lhs), isSequence: false };
  }

  // Multi-key sequence like "gd", "]]", "<Space>f"
  return { canonical: lhs, isSequence: true };
}

// -- Yazi helpers ----------------------------------------------------------

function parseYaziKey(
  on: string,
): { canonical: string; isSequence: boolean } | null {
  // Angle bracket notation: <C-s>, <A-e>, <Enter>, etc.
  const bracketRe = /^<([^>]+)>$/;
  const m = on.match(bracketRe);

  if (m) {
    const inner = m[1];
    const parts = inner.split('-');
    const keyPart = parts[parts.length - 1];
    const modParts = parts.slice(0, -1);

    const mods: string[] = [];
    for (const mp of modParts) {
      const mapped = NVIM_MOD_MAP[mp.toUpperCase()];
      if (mapped) mods.push(mapped);
    }

    const mappedKey = NVIM_KEY_MAP[keyPart.toLowerCase()] ?? keyPart;
    return { canonical: normalizeKey(mods, mappedKey), isSequence: false };
  }

  // Single printable char
  if (on.length === 1) {
    return { canonical: normalizeKey([], on), isSequence: false };
  }

  // Multi-key sequence
  return { canonical: on, isSequence: true };
}

// ---------------------------------------------------------------------------
// Parsers
// ---------------------------------------------------------------------------

// -- WezTerm parser --------------------------------------------------------

interface WezTableInfo {
  name: string;
  content: string;
}

/** Extract named Lua table blocks from keybinds.lua using brace depth tracking. */
function extractLuaTables(source: string): WezTableInfo[] {
  const tables: WezTableInfo[] = [];
  // Match: local <name> = { ... }
  // We find the opening brace and then count depth to find the matching close.
  const tableStartRe = /^local\s+([\w]+)\s*=\s*\{/gm;

  for (
    let match = tableStartRe.exec(source);
    match !== null;
    match = tableStartRe.exec(source)
  ) {
    const name = match[1];
    const startIdx = match.index + match[0].length - 1; // index of '{'
    let depth = 1;
    let i = startIdx + 1;
    // Track string state to ignore braces inside strings
    while (i < source.length && depth > 0) {
      const ch = source[i];
      if (ch === "'" || ch === '"') {
        // Skip string literal
        const quote = ch;
        i++;
        while (i < source.length && source[i] !== quote) {
          if (source[i] === '\\') i++; // skip escaped char
          i++;
        }
      } else if (ch === '-' && source[i + 1] === '-') {
        // Skip line comment
        while (i < source.length && source[i] !== '\n') i++;
      } else if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
      }
      i++;
    }

    tables.push({ name, content: source.slice(startIdx, i) });
  }

  return tables;
}

/** Parse individual key entries from a Lua table string. */
function parseWezEntries(
  tableContent: string,
  tableName: string,
  platform: 'linux' | 'darwin',
  sourceFile: string,
): Keybinding[] {
  const bindings: Keybinding[] = [];

  // Match entries like: { key = 'x', mods = 'MOD', action = act.Something(...) }
  // Also capture preceding comment lines for description.
  const entryRe =
    /\{\s*key\s*=\s*'([^']+)'\s*,\s*mods\s*=\s*'([^']*)'\s*,\s*action\s*=\s*([^}]+(?:\{[^}]*\}[^}]*)*)\}/g;

  for (
    let entryMatch = entryRe.exec(tableContent);
    entryMatch !== null;
    entryMatch = entryRe.exec(tableContent)
  ) {
    const rawKey = entryMatch[1];
    const rawMods = entryMatch[2];
    const actionStr = entryMatch[3].trim();

    // Detect passthrough actions
    const isPassthrough =
      actionStr.startsWith('act.SendKey') ||
      actionStr.startsWith('act.SendString');

    // Extract description from the nearest preceding comment.
    // Look for the main description comment (starting with -- `key combo`),
    // skipping annotation comments like "selene: allow(...)".
    const beforeEntry = tableContent.slice(0, entryMatch.index);
    const commentLines = beforeEntry.split('\n').reverse();
    let description = '';
    for (const line of commentLines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('--')) {
        const commentText = trimmed.replace(/^--\s*/, '');
        // Skip annotation/pragma comments
        if (/^(selene:|@diagnostic)/.test(commentText)) continue;
        description = commentText;
        break;
      }
      if (trimmed === '' || trimmed === ',') continue;
      break;
    }

    const norm = normalizeWeztermKey(rawKey, rawMods, platform);
    if (!norm) continue;

    bindings.push({
      canonical: norm.canonical,
      rawKey: `key='${rawKey}', mods='${rawMods}'`,
      tool: 'wezterm',
      context: tableName,
      description,
      sourceFile,
      isPassthrough,
    });
  }

  return bindings;
}

function parseWezterm(
  root: string,
  platform: 'linux' | 'darwin',
): Keybinding[] {
  const filePath = `${root}/.config/wezterm/keybinds.lua`;
  let source: string;
  try {
    source = Deno.readTextFileSync(filePath);
  } catch {
    console.error(`Warning: ${filePath} not found, skipping WezTerm.`);
    return [];
  }

  const tables = extractLuaTables(source);
  const bindings: Keybinding[] = [];

  for (const table of tables) {
    // Skip tables that don't apply to this platform
    if (platform === 'linux' && table.name === 'darwin_specific_keys') continue;
    if (platform === 'darwin' && table.name === 'windows_specific_keys')
      continue;

    bindings.push(
      ...parseWezEntries(table.content, table.name, platform, filePath),
    );
  }

  return bindings;
}

// -- Neovim parser ---------------------------------------------------------

interface NvimKeymapEntry {
  mode: string;
  lhs: string;
  desc: string;
}

async function parseNeovim(): Promise<Keybinding[]> {
  const luaScript = `
local maps = {}
for _, mode in ipairs({"n","i","v","x","o","c","s"}) do
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    table.insert(maps, {
      mode = m.mode,
      lhs = m.lhs,
      desc = m.desc or "",
    })
  end
end
print(vim.json.encode(maps))
`.trim();

  try {
    const cmd = new Deno.Command('nvim', {
      args: ['--headless', '-c', `lua ${luaScript}`, '-c', 'qa'],
      stdout: 'piped',
      stderr: 'piped',
    });

    const output = await cmd.output();
    // nvim --headless sends print() output to stderr
    const raw = new TextDecoder().decode(output.stderr).trim();
    // Strip carriage returns from nvim output
    const stdout = raw.replace(/\r/g, '');

    // nvim may print extra lines; find the JSON line
    const lines = stdout.split('\n');
    let jsonLine = '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        jsonLine = trimmed;
        break;
      }
    }

    if (!jsonLine) {
      console.error('Warning: Could not get keymaps from Neovim.');
      return [];
    }

    const entries: NvimKeymapEntry[] = JSON.parse(jsonLine);
    const bindings: Keybinding[] = [];

    for (const entry of entries) {
      const parsed = parseNvimLhs(entry.lhs);
      if (!parsed || parsed.isSequence) continue;

      bindings.push({
        canonical: parsed.canonical,
        rawKey: entry.lhs,
        tool: 'neovim',
        context: entry.mode,
        description: entry.desc,
        sourceFile: '(nvim keymap)',
        isPassthrough: false,
      });
    }

    return bindings;
  } catch (e) {
    console.error(`Warning: Could not run nvim: ${e}`);
    return [];
  }
}

// -- Yazi parser -----------------------------------------------------------

interface YaziKeymapSection {
  prepend_keymap?: Array<{ on: string; run: string; desc?: string }>;
}

interface YaziKeymap {
  mgr?: YaziKeymapSection;
  [key: string]: YaziKeymapSection | undefined;
}

function parseYazi(root: string): Keybinding[] {
  const filePath = `${root}/.config/yazi/keymap.toml`;
  let source: string;
  try {
    source = Deno.readTextFileSync(filePath);
  } catch {
    console.error(`Warning: ${filePath} not found, skipping Yazi.`);
    return [];
  }

  const parsed = parseTOML(source) as unknown as YaziKeymap;
  const bindings: Keybinding[] = [];

  for (const [sectionName, section] of Object.entries(parsed)) {
    if (!section || typeof section !== 'object') continue;

    const keymaps = section.prepend_keymap;
    if (!Array.isArray(keymaps)) continue;

    for (const entry of keymaps) {
      const on = entry.on;
      if (typeof on !== 'string') continue;

      const result = parseYaziKey(on);
      if (!result || result.isSequence) continue;

      bindings.push({
        canonical: result.canonical,
        rawKey: on,
        tool: 'yazi',
        context: sectionName,
        description: entry.desc ?? '',
        sourceFile: filePath,
        isPassthrough: false,
      });
    }
  }

  return bindings;
}

// ---------------------------------------------------------------------------
// Conflict detection
// ---------------------------------------------------------------------------

function detectConflicts(bindings: Keybinding[]): Conflict[] {
  // Group by canonical key
  const groups = new Map<string, Keybinding[]>();
  for (const b of bindings) {
    const existing = groups.get(b.canonical) ?? [];
    existing.push(b);
    groups.set(b.canonical, existing);
  }

  const conflicts: Conflict[] = [];

  for (const [canonical, group] of groups) {
    const tools = new Set(group.map((b) => b.tool));
    if (tools.size < 2) continue;

    const weztermBindings = group.filter((b) => b.tool === 'wezterm');
    const neovimBindings = group.filter((b) => b.tool === 'neovim');
    const yaziBindings = group.filter((b) => b.tool === 'yazi');

    // WezTerm normal-mode (non-passthrough, non-copy/search mode) bindings
    const weztermNormal = weztermBindings.filter(
      (b) =>
        !b.isPassthrough &&
        b.context !== 'copy_mode' &&
        b.context !== 'search_mode',
    );

    // WezTerm vs Neovim
    if (weztermNormal.length > 0 && neovimBindings.length > 0) {
      conflicts.push({
        canonical,
        severity: 'critical',
        label: 'WezTerm intercepts before Neovim',
        bindings: [...weztermNormal, ...neovimBindings],
      });
    }

    // WezTerm vs Yazi
    if (weztermNormal.length > 0 && yaziBindings.length > 0) {
      conflicts.push({
        canonical,
        severity: 'critical',
        label: 'WezTerm intercepts before Yazi',
        bindings: [...weztermNormal, ...yaziBindings],
      });
    }

    // Neovim vs Yazi (informational)
    if (neovimBindings.length > 0 && yaziBindings.length > 0) {
      conflicts.push({
        canonical,
        severity: 'info',
        label: 'Neovim vs Yazi (different tools, same key)',
        bindings: [...neovimBindings, ...yaziBindings],
      });
    }
  }

  // Sort: critical first, then by canonical key
  conflicts.sort((a, b) => {
    if (a.severity !== b.severity) return a.severity === 'critical' ? -1 : 1;
    return a.canonical.localeCompare(b.canonical);
  });

  return conflicts;
}

// ---------------------------------------------------------------------------
// Reporter
// ---------------------------------------------------------------------------

function formatBinding(b: Keybinding): string {
  const loc =
    b.tool === 'neovim'
      ? `${b.context} mode`
      : `${b.sourceFile.split('/').pop()}, ${b.context}`;
  const desc = b.description ? b.description : '(no description)';
  const toolLabel = b.tool.charAt(0).toUpperCase() + b.tool.slice(1);
  return `    ${toolLabel}: ${desc} (${loc})`;
}

function formatKeyDisplay(canonical: string): string {
  return canonical
    .split('+')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('+');
}

function reportText(
  conflicts: Conflict[],
  passthroughBindings: Keybinding[],
  allBindings: Keybinding[],
  opts: Options,
): void {
  const modsInfo =
    opts.platform === 'darwin'
      ? 'PRIMARY=CTRL, SECONDARY=ALT'
      : 'PRIMARY=CTRL, SECONDARY=ALT';

  console.log('=== Keybinding Conflict Report ===');
  console.log(`Platform: ${opts.platform} (${modsInfo})`);
  console.log();

  // Critical conflicts
  const critical = conflicts.filter((c) => c.severity === 'critical');
  const info = conflicts.filter((c) => c.severity === 'info');

  if (critical.length > 0) {
    // Group by label
    const byLabel = new Map<string, Conflict[]>();
    for (const c of critical) {
      const existing = byLabel.get(c.label) ?? [];
      existing.push(c);
      byLabel.set(c.label, existing);
    }

    for (const [label, items] of byLabel) {
      console.log(`--- CRITICAL: ${label} ---`);
      for (const item of items) {
        console.log(`  ${formatKeyDisplay(item.canonical)}`);
        for (const b of item.bindings) {
          console.log(formatBinding(b));
        }
      }
      console.log();
    }
  }

  if (info.length > 0) {
    console.log('--- INFO: Neovim vs Yazi (different tools, same key) ---');
    for (const item of info) {
      console.log(`  ${formatKeyDisplay(item.canonical)}`);
      for (const b of item.bindings) {
        console.log(formatBinding(b));
      }
    }
    console.log();
  }

  if (passthroughBindings.length > 0) {
    console.log('--- Passthrough keys (WezTerm forwards to terminal) ---');
    for (const b of passthroughBindings) {
      console.log(
        `  ${formatKeyDisplay(b.canonical)}: ${b.description || '(no description)'} (passthrough)`,
      );
    }
    console.log();
  }

  // Summary
  console.log('=== Summary ===');
  console.log(`  Critical conflicts: ${critical.length}`);
  console.log(`  Informational overlaps: ${info.length}`);
  console.log(`  Passthrough keys: ${passthroughBindings.length}`);

  if (opts.verbose) {
    console.log();
    console.log('=== All Keybindings ===');
    const byTool = new Map<string, Keybinding[]>();
    for (const b of allBindings) {
      const existing = byTool.get(b.tool) ?? [];
      existing.push(b);
      byTool.set(b.tool, existing);
    }

    for (const tool of ['wezterm', 'neovim', 'yazi'] as const) {
      const toolBindings = byTool.get(tool) ?? [];
      if (toolBindings.length === 0) continue;
      console.log();
      console.log(
        `--- ${tool.charAt(0).toUpperCase() + tool.slice(1)} (${toolBindings.length} bindings) ---`,
      );
      for (const b of toolBindings) {
        const desc = b.description || '(no description)';
        const pt = b.isPassthrough ? ' [passthrough]' : '';
        console.log(
          `  ${formatKeyDisplay(b.canonical).padEnd(24)} ${b.context.padEnd(14)} ${desc}${pt}`,
        );
      }
    }
  }
}

interface JsonReport {
  platform: string;
  conflicts: Array<{
    key: string;
    severity: string;
    label: string;
    bindings: Array<{
      tool: string;
      rawKey: string;
      context: string;
      description: string;
      sourceFile: string;
      isPassthrough: boolean;
    }>;
  }>;
  passthrough: Array<{
    key: string;
    rawKey: string;
    description: string;
  }>;
  summary: {
    critical: number;
    info: number;
    passthrough: number;
    totalBindings: number;
  };
}

function reportJson(
  conflicts: Conflict[],
  passthroughBindings: Keybinding[],
  allBindings: Keybinding[],
  opts: Options,
): void {
  const critical = conflicts.filter((c) => c.severity === 'critical');
  const info = conflicts.filter((c) => c.severity === 'info');

  const report: JsonReport = {
    platform: opts.platform,
    conflicts: conflicts.map((c) => ({
      key: c.canonical,
      severity: c.severity,
      label: c.label,
      bindings: c.bindings.map((b) => ({
        tool: b.tool,
        rawKey: b.rawKey,
        context: b.context,
        description: b.description,
        sourceFile: b.sourceFile,
        isPassthrough: b.isPassthrough,
      })),
    })),
    passthrough: passthroughBindings.map((b) => ({
      key: b.canonical,
      rawKey: b.rawKey,
      description: b.description,
    })),
    summary: {
      critical: critical.length,
      info: info.length,
      passthrough: passthroughBindings.length,
      totalBindings: allBindings.length,
    },
  };

  console.log(JSON.stringify(report, null, 2));
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const opts = parseArgs([...Deno.args]);
  const root = findDotfilesRoot();

  // Collect keybindings from all tools
  const weztermBindings = parseWezterm(root, opts.platform);
  const neovimBindings = await parseNeovim();
  const yaziBindings = parseYazi(root);

  const allBindings = [...weztermBindings, ...neovimBindings, ...yaziBindings];

  // Passthrough keys
  const passthroughBindings = weztermBindings.filter((b) => b.isPassthrough);

  // Detect conflicts
  const conflicts = detectConflicts(allBindings);

  // Report
  if (opts.json) {
    reportJson(conflicts, passthroughBindings, allBindings, opts);
  } else {
    reportText(conflicts, passthroughBindings, allBindings, opts);
  }

  // Exit with code 1 if there are critical conflicts
  const hasCritical = conflicts.some((c) => c.severity === 'critical');
  if (hasCritical) Deno.exit(1);
}

main();
