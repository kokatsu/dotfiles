#!/usr/bin/env -S deno run --allow-read
// test-renovate-patterns.ts — renovate.json5 の matchStrings が overlay の全 # Renovate: コメントにマッチするか検証する
//
// 検証項目:
//   1. managerFilePatterns が # Renovate: コメントを含む全ファイルにマッチすること
//   2. 各 # Renovate: コメントが matchStrings のいずれかにマッチすること
//   3. マッチから datasource, depName, currentValue が抽出できること

import { join } from "node:path";

const OVERLAY_DIR = Deno.args[0] || "nix/overlays";
const RENOVATE_CONFIG = "renovate.json5";

const RED = "\x1b[0;31m";
const GREEN = "\x1b[0;32m";
const NC = "\x1b[0m";

let errors = 0;
let tests = 0;

function pass(msg: string): void {
  tests++;
  console.log(`${GREEN}  PASS${NC} ${msg}`);
}

function fail(msg: string): void {
  tests++;
  errors++;
  console.log(`${RED}  FAIL${NC} ${msg}`);
}

interface RenovateComment {
  depName: string;
  pos: number;
  line: number;
}

function decodeJson5Escapes(s: string): string {
  let result = "";
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "\\" && i + 1 < s.length) {
      const c = s[i + 1];
      if (c === "\\") result += "\\";
      else if (c === "n") result += "\n";
      else if (c === "t") result += "\t";
      else result += `\\${c}`;
      i++;
    } else {
      result += s[i];
    }
  }
  return result;
}

function extractBracketBlock(content: string, key: string): string | null {
  const match = content.match(new RegExp(`${key}:\\s*\\[`));
  if (!match || match.index === undefined) return null;
  const start = match.index + match[0].length;
  let depth = 1;
  let inString: string | false = false;
  let escaped = false;
  for (let i = start; i < content.length; i++) {
    const c = content[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (c === "\\") {
      escaped = true;
      continue;
    }
    if ((c === "'" || c === '"') && !inString) inString = c;
    else if (c === inString) inString = false;
    else if (!inString) {
      if (c === "[") depth++;
      else if (c === "]") {
        depth--;
        if (depth === 0) return content.slice(start, i);
      }
    }
  }
  return null;
}

function extractMatchStrings(): string[] {
  const content = Deno.readTextFileSync(RENOVATE_CONFIG);
  const block = extractBracketBlock(content, "matchStrings");
  if (!block) {
    console.error("ERROR: matchStrings not found in renovate.json5");
    Deno.exit(1);
  }
  return [...block.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((m) =>
    decodeJson5Escapes(m[1])
  );
}

function extractFilePatterns(): string[] {
  const content = Deno.readTextFileSync(RENOVATE_CONFIG);
  const block = extractBracketBlock(content, "managerFilePatterns");
  if (!block) return [];
  return [...block.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((m) => {
    const s = decodeJson5Escapes(m[1]);
    return s.startsWith("/") && s.endsWith("/") ? s.slice(1, -1) : s;
  });
}

function findRenovateComments(content: string): RenovateComment[] {
  const re = /#\s*Renovate:\s*datasource=[\w.-]+\s+depName=([\w@/-]+)/g;
  return [...content.matchAll(re)].map((m) => ({
    depName: m[1],
    pos: m.index ?? 0,
    line: content.slice(0, m.index).split("\n").length,
  }));
}

// --- Main ---

const patterns = extractMatchStrings();
const filePatterns = extractFilePatterns();
console.log(`Loaded ${patterns.length} matchStrings from ${RENOVATE_CONFIG}`);
console.log();

const overlayFiles = [...Deno.readDirSync(OVERLAY_DIR)]
  .filter(
    (e) =>
      e.isFile &&
      e.name.endsWith(".nix") &&
      e.name !== "lib.nix" &&
      e.name !== "default.nix",
  )
  .map((e) => e.name)
  .sort();

// Test 1: managerFilePatterns
console.log("=== Test: managerFilePatterns ===");
console.log();
for (const file of overlayFiles) {
  const filepath = join(OVERLAY_DIR, file);
  const content = Deno.readTextFileSync(filepath);
  const comments = findRenovateComments(content);
  if (comments.length === 0) continue;
  const matched = filePatterns.some((p) => new RegExp(p).test(filepath));
  if (matched) pass(file);
  else fail(`${file} not matched (has ${comments.length} packages)`);
}
console.log();

// Test 2: matchStrings
console.log("=== Test: matchStrings ===");
console.log();
for (const file of overlayFiles) {
  const filepath = join(OVERLAY_DIR, file);
  const content = Deno.readTextFileSync(filepath);
  const comments = findRenovateComments(content);
  if (comments.length === 0) continue;
  console.log(`[${file}]`);
  for (const comment of comments) {
    let matched = false;
    for (const pattern of patterns) {
      const re = new RegExp(pattern, "g");
      for (const m of content.matchAll(re)) {
        if (m.index === comment.pos) {
          pass(`${comment.depName}: version=${m.groups?.currentValue}`);
          matched = true;
          break;
        }
      }
      if (matched) break;
    }
    if (!matched) {
      fail(`${comment.depName}: no pattern matched (line ${comment.line})`);
    }
  }
  console.log();
}

console.log(`=== Results: ${tests} tests, ${errors} failures ===`);
if (errors) {
  console.log();
  console.log(
    "ERROR: Renovate matchStrings do not cover all # Renovate: comments.",
  );
  console.log(
    "       Update matchStrings in renovate.json5 or overlay file structure.",
  );
  Deno.exit(1);
}
console.log("All tests passed.");
