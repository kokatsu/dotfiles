---
name: browser-research
description: Research web pages with the shared Claude browser-research skill through agent-browser when Codex needs a rendered JavaScript-capable browser fallback. Use when WebSearch or WebFetch is insufficient, a provided URL requires JS rendering, a SPA or dynamic docs page must be investigated, multi-page documentation navigation is needed, or a web page cannot be parsed by normal fetch tools.
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
- Prefer read-only browsing. Do not submit forms, authenticate, purchase, or trigger state-changing actions unless the user explicitly approves the exact action.
- Always close any `agent-browser` session you open.
- If the Claude skill conflicts with active Codex/system/developer instructions, follow the active Codex/system/developer instructions.
