---
name: browser-research
description: Research web pages with agent-browser when normal fetching is insufficient or rendered content and browser navigation are needed.
---

# Browser Research

## Overview

Use this as a Codex adapter for the canonical Claude skill at `~/.config/claude/skills/browser-research/SKILL.md`.
It keeps the detailed agent-browser workflow in one place while exposing Codex-compatible skill metadata.

## Workflow

Before researching, read the canonical skill:

```bash
sed -n '1,260p' "${XDG_CONFIG_HOME:-$HOME/.config}/claude/skills/browser-research/SKILL.md"
```

Follow that skill's workflow and critical rules, with these Codex compatibility notes:

- Ignore Claude-only frontmatter such as `allowed-tools`.
- Map `Bash(...)`, `Read`, and `Write` references to the shell and filesystem tools available in the active Codex session.
- Respect the active Codex sandbox, approval, network, and browsing instructions before running `agent-browser` or writing files.
- Keep research read-only. An explicitly requested action outside research follows the active session instructions and existing user authorization.
- Resolve canonical references relative to the Claude skill directory; Codex does not supply `CLAUDE_SKILL_DIR`. Close only sessions opened for this task.
- Explicit user instructions override skill workflow preferences; system and developer instructions remain authoritative.
