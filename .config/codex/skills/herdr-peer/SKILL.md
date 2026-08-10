---
name: herdr-peer
description: Safely consult the opposite Claude or Codex agent in the same Herdr tab through the guarded herdr-peer command. Use when the user explicitly asks Claude and Codex to collaborate, asks one agent to consult or review with the other, or invokes herdr-peer. Do not use for implicit delegation or ordinary background work.
---

# Herdr Peer

Use this as the Codex adapter for the canonical Claude skill at `~/.config/claude/skills/herdr-peer/SKILL.md`.

Before acting, read the canonical skill completely:

```bash
sed -n '1,240p' "${XDG_CONFIG_HOME:-$HOME/.config}/claude/skills/herdr-peer/SKILL.md"
```

Follow its workflow and guardrails. Invoke only the installed `herdr-peer` command; never replace it with raw Herdr prompt or pane-input commands. Respect the active Codex sandbox and approval requirements. If any active instruction conflicts with the canonical skill, follow the active instruction.

Herdr's Unix socket is not reachable from the default network-disabled `workspace-write` sandbox. Run every `herdr-peer` command outside that sandbox by setting `sandbox_permissions` to `require_escalated`; use the scoped `herdr-peer` prefix when requesting persistent approval. Do not rely on an execpolicy allow rule to grant socket access, and do not retry the command inside the sandbox first.
