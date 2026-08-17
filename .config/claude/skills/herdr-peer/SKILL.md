---
name: herdr-peer
description: Safely consult the opposite Claude or Codex agent in the same Herdr tab through the guarded herdr-peer command. Use when the user explicitly asks Claude and Codex to collaborate, asks one agent to consult or review with the other, or invokes herdr-peer. Do not use for implicit delegation or ordinary background work.
---

# Herdr Peer

Use `herdr-peer`; never call raw Herdr input commands directly. The wrapper resolves exactly one opposite agent in the current tab and rechecks self-targeting, ambiguity, readiness, and agent-session replacement immediately before sending. A newly opened agent may not have a native session ID until its first prompt; the wrapper permits only that null-to-initialized transition while keeping the pane, tab, workspace, agent-kind, and readiness checks in place. Empty or non-string session IDs are invalid rather than uninitialized.

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

The deterministic wrapper is installed from `scripts/herdr-peer` as the `herdr-peer` command. Its recheck and the shared command hook are best-effort guardrails, not a security boundary for arbitrary Bash execution. When a peer already has a session ID, any change remains a hard failure. When the ID is initially null, the wrapper rechecks that it is still null immediately before prompting and requires a non-null ID afterward. Read-only `resolve` and `read` operations accept a concurrent null-to-initialized transition after the identity checks. If post-prompt initialization fails, the prompt has already been delivered and must not be retried automatically. Atomic protection against replacement during either path requires Herdr to compare an expected agent session ID or pane-occupant generation inside the socket operation that submits the prompt.
