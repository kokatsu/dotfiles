---
name: herdr-peer
description: Safely consult the opposite Claude or Codex agent in the same Herdr tab through the guarded herdr-peer command. Use when the user explicitly asks Claude and Codex to collaborate, asks one agent to consult or review with the other, or invokes herdr-peer. Do not use for implicit delegation or ordinary background work.
---

# Herdr Peer

Use `herdr-peer`; never call raw Herdr input commands directly. The wrapper resolves exactly one opposite agent in the current tab and rechecks self-targeting, ambiguity, readiness, and agent-session replacement immediately before sending.

## Workflow

1. Confirm the selected peer without changing state:

   ```bash
   herdr-peer resolve
   ```

2. Send one complete, self-contained request and wait for the peer to settle:

   ```bash
   herdr-peer prompt "Review the current diff and report only actionable findings."
   ```

   Use `--timeout <milliseconds>` before the quoted prompt only when the default five minutes is unsuitable.

3. Read the peer's response:

   ```bash
   herdr-peer read
   ```

   Use `--lines <count>` when more context is needed.

4. Integrate the result and respond to the user. If the peer becomes `blocked` or the command times out, inspect with `herdr-peer read` and report the blocker instead of guessing.

## Coordination rules

- Send only when the user explicitly requested Claude/Codex collaboration.
- Keep the peer request self-contained and state whether it is read-only or may edit files.
- Do not invoke this skill in response to a peer-originated prompt; return the result to the caller and prevent delegation loops.
- Do not bypass `herdr-peer` with raw Herdr prompt or pane-input commands.
- Treat resolution or validation failure as a hard stop. Do not select another tab, workspace, or agent manually.

The deterministic wrapper is installed from `scripts/herdr-peer` as the `herdr-peer` command. Its recheck and the shared command hook are best-effort guardrails, not a security boundary for arbitrary Bash execution. Atomic protection against session replacement requires Herdr to compare an expected agent session ID inside the socket operation that submits the prompt.
