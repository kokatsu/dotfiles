#!/usr/bin/env -S deno run --allow-read
// test-renovate-patterns.ts — renovate.json5 の regex manager が # Renovate: コメントを
// 全て拾えるか検証する。overlay (nix/overlays/*.nix) 用と flake.nix のタグ pin 用の
// 2 つの customManagers を、それぞれの managerFilePatterns が指すファイルで検査する。
//
// 検証項目:
//   1. # Renovate: コメントを含む各ファイルが、いずれかの manager の
//      managerFilePatterns にマッチすること
//   2. その manager の matchStrings のいずれかがコメント位置にマッチすること
//   3. マッチから currentValue が抽出できること

import { join } from "node:path";

const OVERLAY_DIR = Deno.args[0] || "nix/overlays";
const RENOVATE_CONFIG = "renovate.json5";
// overlay 以外で # Renovate: コメントを持つファイル
const EXTRA_FILES = ["flake.nix"];

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

interface RegexManager {
  filePatterns: string[];
  matchStrings: string[];
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

/** `key: [` から対応する `]` までの中身を返す。from 以降の最初の出現を探す */
function extractBracketBlock(
  content: string,
  key: string,
  from = 0,
): { body: string; end: number } | null {
  const re = new RegExp(`${key}:\\s*\\[`, "g");
  re.lastIndex = from;
  const match = re.exec(content);
  if (!match) return null;
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
        if (depth === 0) return { body: content.slice(start, i), end: i };
      }
    }
  }
  return null;
}

function stringLiterals(block: string): string[] {
  return [...block.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((m) =>
    decodeJson5Escapes(m[1])
  );
}

/** customManagers の各 regex manager を、出現順に (managerFilePatterns, matchStrings) の組で返す */
function extractRegexManagers(): RegexManager[] {
  const content = Deno.readTextFileSync(RENOVATE_CONFIG);
  const managers: RegexManager[] = [];
  let cursor = 0;
  for (;;) {
    const files = extractBracketBlock(content, "managerFilePatterns", cursor);
    if (!files) break;
    const strings = extractBracketBlock(content, "matchStrings", files.end);
    if (!strings) {
      console.error(
        "ERROR: managerFilePatterns without matchStrings in renovate.json5",
      );
      Deno.exit(1);
    }
    managers.push({
      filePatterns: stringLiterals(files.body).map((s) =>
        s.startsWith("/") && s.endsWith("/") ? s.slice(1, -1) : s
      ),
      matchStrings: stringLiterals(strings.body),
    });
    cursor = strings.end;
  }
  if (managers.length === 0) {
    console.error("ERROR: no regex manager found in renovate.json5");
    Deno.exit(1);
  }
  return managers;
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

const managers = extractRegexManagers();
console.log(
  `Loaded ${managers.length} regex managers from ${RENOVATE_CONFIG}`,
);
console.log();

const overlayFiles = [...Deno.readDirSync(OVERLAY_DIR)]
  .filter(
    (e) =>
      e.isFile &&
      e.name.endsWith(".nix") &&
      e.name !== "lib.nix" &&
      e.name !== "default.nix",
  )
  .map((e) => join(OVERLAY_DIR, e.name))
  .sort();
const targetFiles = [...overlayFiles, ...EXTRA_FILES];

for (const filepath of targetFiles) {
  const content = Deno.readTextFileSync(filepath);
  const comments = findRenovateComments(content);
  if (comments.length === 0) continue;
  console.log(`[${filepath}]`);

  // Test 1: どの manager がこのファイルを担当するか
  const owners = managers.filter((m) =>
    m.filePatterns.some((p) => new RegExp(p).test(filepath))
  );
  if (owners.length === 0) {
    fail(
      `no managerFilePatterns match (has ${comments.length} packages)`,
    );
    console.log();
    continue;
  }
  pass(`matched by ${owners.length} manager(s)`);

  // Test 2: 各コメントがその manager の matchStrings にマッチする
  for (const comment of comments) {
    let matched = false;
    for (const owner of owners) {
      for (const pattern of owner.matchStrings) {
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
    "       Update matchStrings in renovate.json5 or the file structure.",
  );
  Deno.exit(1);
}
console.log("All tests passed.");
