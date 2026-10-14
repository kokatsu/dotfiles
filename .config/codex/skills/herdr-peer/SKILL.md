---
name: herdr-peer
description: Request research, implementation, or review from the opposite Claude or Codex agent in the same Herdr tab, with results saved to files, when the user explicitly requests cross-agent collaboration or invokes herdr-peer.
---

# Herdr Peer

Use this as the Codex adapter for the canonical Claude skill at `~/.config/claude/skills/herdr-peer/SKILL.md`.

Before acting, read the canonical skill completely:

```bash
sed -n '1,240p' "${XDG_CONFIG_HOME:-$HOME/.config}/claude/skills/herdr-peer/SKILL.md"
```

Follow its workflow and guardrails. Invoke only the installed `herdr-peer` command; never replace it with raw Herdr prompt or pane-input commands. Respect the active Codex sandbox and approval requirements. Resolve its references relative to the Claude skill directory. Explicit user instructions override skill workflow preferences; system and developer instructions remain authoritative.

Select research, implementation, or review from the user's request; default to a read-only review when unspecified. Read the canonical skill's `references/tasks.md` and `references/transport.md` for request templates, saved results, execution handles, and timeout recovery. Implementation remains limited to the user's authorized scope.

Herdr's Unix socket is not reachable from the default network-disabled `workspace-write` sandbox. Run every `herdr-peer` command outside that sandbox by setting `sandbox_permissions` to `require_escalated`; use the scoped `herdr-peer` prefix when requesting persistent approval. Do not rely on an execpolicy allow rule to grant socket access, and do not retry the command inside the sandbox first.
