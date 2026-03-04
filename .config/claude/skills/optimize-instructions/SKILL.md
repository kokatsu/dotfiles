---
name: optimize-instructions
description: This skill should be used when the user asks to "optimize CLAUDE.md", "review CLAUDE.md", "clean up instructions", "CLAUDE.md最適化", "指示ファイルの見直し", "CLAUDE.mdの無駄を削除".
version: 1.0.0
allowed-tools:
  - Read
  - Glob
  - Grep
  - Edit
  - Agent
  - AskUserQuestion
---

# Optimize Instructions

Review CLAUDE.md for redundant or unnecessary content and suggest improvements. Based on the research finding that instruction files should only contain information agents cannot discover on their own.

## Principle

CLAUDE.md is injected as a User Message (not System Prompt) at session start. As conversation progresses, its influence fades because it becomes an old message buried under newer ones. Therefore, CLAUDE.md should act as a **Session Start Hook** — containing only information needed at session initialization, not persistent rules.

Instruction files hurt performance when they contain:

1. **Discoverable information** — content the agent can find by exploring the codebase
2. **Duplicated documentation** — content that repeats README, inline comments, or config files
3. **General knowledge** — well-known facts about tools/frameworks
4. **Internal redundancy** — the same information repeated within CLAUDE.md itself
5. **Persistent rules in CLAUDE.md** — rules meant to be enforced throughout the session (they fade as conversation grows)

CLAUDE.md should contain:

1. **Project overview** — what the project is and does (helps initial exploration)
2. **Module/directory guide** — structure that is not obvious from directory names alone
3. **Session start procedures** — steps to run at the beginning of each session

`.claude/rules/` should contain:

1. **Coding rules** — naming conventions, style choices, patterns to follow
2. **Project conventions** — commit message format, branching strategy
3. **Non-obvious commands** — specific tool flags, lint configurations
4. **Critical warnings** — things that cause hard-to-debug failures if ignored
5. **Workflow rules** — constraints the agent cannot infer (e.g., "never edit ~/.config/ directly")

Rules in `.claude/rules/` are injected as conditional rules when relevant files are first touched, so they arrive as newer messages closer to the actual work.

## Workflow

### 1. Locate instruction files

Find all instruction files in the project:

- `CLAUDE.md` (project root and subdirectories)
- `.claude/rules/*.md` (rule files)
- `AGENTS.md`, `.cursorrules` etc. (if present)

### 2. Read all instruction files

Read the full content of every instruction file found. Also check for cross-file redundancy (e.g., CLAUDE.md and rules covering the same topic).

### 3. Gather context

Use the Explore agent to check what information is already discoverable:

- **README files** — compare for duplication
- **Directory structure** — check if Architecture/Structure sections are redundant
- **Config files** — check if documented settings are self-evident from the files
- **Package manifests** — check if dependency info duplicates package.json, flake.nix, etc.

### 4. Classify each section/bullet

For every section or bullet point in CLAUDE.md and each rule file, classify it:

| Category | Action | Example |
|----------|--------|---------|
| Discoverable | Remove | "Directory structure: src/ contains..." |
| Duplicated | Remove | Content that mirrors README |
| General knowledge | Remove | "Flakes provide reproducibility" |
| Internal redundancy | Merge or remove | Same info in two sections |
| Project overview | Keep in CLAUDE.md | "ECサイトのバックエンドAPI" |
| Module guide | Keep in CLAUDE.md | Module descriptions not obvious from names |
| Session start procedure | Keep in CLAUDE.md | "Create worktree with feat/{issue}-{name}" |
| Coding rule | Move to `.claude/rules/` | "Use interface over type in TypeScript" |
| Project convention | Move to `.claude/rules/` | Commit message format |
| Non-obvious command | Move to `.claude/rules/` | Specific lint/format commands |
| Critical warning | Move to `.claude/rules/` | "Secretlint prevents committing secrets" |
| Workflow rule | Move to `.claude/rules/` | "Never edit ~/.config/ directly" |

### 5. Present findings

Report findings organized as:

```markdown
## 分析結果

### 削除候補 (Items to remove)
- **項目名** — 理由 (discoverable / duplicated / general knowledge / redundancy)

### CLAUDE.mdに保持 (Keep in CLAUDE.md)
- **項目名** — 理由 (project overview / module guide / session start procedure)

### `.claude/rules/` に移動 (Move to rules)
- **項目名** — 理由 (coding rule / convention / warning / workflow rule)
- Suggest appropriate `paths` frontmatter if the rule applies to specific file patterns

### 改善提案 (Improvements)
- Suggestions for restructuring, merging, or rewording
```

### 6. Ask for confirmation

Use AskUserQuestion to confirm which items to remove before making changes.

### 7. Apply changes

Edit CLAUDE.md and/or rule files based on confirmed actions:

- **Remove**: Delete the item entirely
- **Keep in CLAUDE.md**: Leave as-is
- **Move to rules**: Remove from CLAUDE.md and create/update the appropriate `.claude/rules/*.md` file with `paths` frontmatter if applicable

## Notes

- Always respond in Japanese
- Do not remove items without user confirmation
- Focus on reduction, not addition — shorter instruction files are the goal
- Check for cross-file redundancy between CLAUDE.md and rule files
- Consider that some "discoverable" info may still be worth keeping if discovery is slow or unreliable
