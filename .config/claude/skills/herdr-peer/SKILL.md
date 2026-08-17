---
name: herdr-peer
description: Safely consult the opposite Claude or Codex agent in the same Herdr tab through the guarded herdr-peer command. Use when the user explicitly asks Claude and Codex to collaborate, asks one agent to consult or review with the other, or invokes herdr-peer. When invoked without an additional task, default to a read-only review of the current task's edits, including known non-sensitive gitignored edits. If fixes are authorized, re-review them until both agents agree that no actionable findings remain; otherwise report findings and stop without editing. Do not use for implicit delegation or ordinary background work.
---

# Herdr Peer

Use `herdr-peer`; never call raw Herdr input commands directly. The wrapper resolves exactly one opposite agent in the current tab and rechecks self-targeting, ambiguity, readiness, and agent-session replacement immediately before sending. A newly opened agent may not have a native session ID until its first prompt; the wrapper permits only that null-to-initialized transition while keeping the pane, tab, workspace, agent-kind, and readiness checks in place. Empty or non-string session IDs are invalid rather than uninitialized.

## Default review scope

When invoked without an additional task or review scope, request a read-only review of the edits made for the current task.

- Build a self-contained request that accounts for every path known to have been edited or created for the task, including staged, unstaged, untracked, and gitignored paths, subject to the sensitive-content rule below.
- Use the current conversation and tool history to identify gitignored edits; `git status` and `git diff` do not enumerate them. For each ignored path, state whether it was created or modified and give enough task intent for a meaningful review.
- Ask for only actionable findings, ordered by severity with file and line references. If none exist, ask the peer to say so explicitly.
- Do not scan or include every ignored file. Include only ignored paths known to have been edited for the current task.
- For any edited file that may contain credentials or other secrets, do not ask the peer to open it and do not include its raw contents. Provide a redacted diff or summary with all secret values removed when that permits a meaningful review; otherwise exclude the contents and report the resulting review limitation. Treat the path itself as sensitive when applicable.
- If no task-local edited paths are known, fall back to the current staged, unstaged, and untracked working-tree changes and state that no known gitignored edit was identified.

## Review loop

After receiving actionable findings, verify each one against the local files before changing anything. When the current task authorizes a fix, make the smallest valid fix and request another read-only review from the same peer. Without authorization to fix, report the findings and stop; do not repeatedly review unchanged files.

- In every follow-up request, restate the full review scope, list the prior findings and their dispositions, and name every path changed since the previous review, including known gitignored paths.
- Record the peer identity from the initial resolution. Before every follow-up, make a best-effort comparison of the tab, workspace, pane, agent kind, and session ID; allow only the initial null-to-initialized session transition when all other identity fields still match. Stop on a detected replacement instead of continuing with a different agent. This comparison is not atomic with the later prompt submission.
- Repeat verification, repair, and follow-up review when the peer reports a valid remaining or newly introduced finding.
- Finish only when the local agent finds no unresolved actionable issue and the peer explicitly reports no actionable findings. Report that agreement to the user; do not infer it from silence or a partial response.
- If the agents disagree, compare concrete file and line evidence and continue only when the resolution is supported by the repository. Do not change code merely to mirror the peer's opinion.
- Stop and report the blocker instead of claiming agreement when progress requires new user authority, the peer cannot be reached safely, or the disagreement cannot be resolved from available evidence.

## Workflow

1. Confirm the selected peer without changing state:

   ```bash
   herdr-peer resolve
   ```

2. Send one complete, self-contained request and wait for the peer to settle:

   ```bash
   herdr-peer prompt "Read-only review. Task intent: INTENT. Review these edited paths: PATHS. Known non-sensitive gitignored edits: PATHS_OR_NONE. Sensitive edits omitted or redacted: SUMMARY_OR_NONE. Report only actionable findings with file and line references; explicitly say when none remain."
   ```

   Replace the uppercase placeholders with task-specific values before sending.

   Use `--timeout <milliseconds>` before the quoted prompt only when the default five minutes is unsuitable.

3. Read the peer's response:

   ```bash
   herdr-peer read
   ```

   Use `--lines <count>` when more context is needed.

4. Integrate the result. If an authorized fix is made from the review, repeat steps 1–3 with the follow-up context required by the review loop before responding to the user. If the peer becomes `blocked` or the command times out, inspect with `herdr-peer read` and report the blocker instead of guessing.

## Coordination rules

- Send only when the user explicitly requested Claude/Codex collaboration.
- Keep the peer request self-contained and state whether it is read-only or may edit files.
- Do not invoke this skill in response to a peer-originated prompt; return the result to the caller and prevent delegation loops.
- Do not bypass `herdr-peer` with raw Herdr prompt or pane-input commands.
- Treat resolution or validation failure as a hard stop. Do not select another tab, workspace, or agent manually.

The deterministic wrapper is installed from `scripts/herdr-peer` as the `herdr-peer` command. Its recheck and the shared command hook are best-effort guardrails, not a security boundary for arbitrary Bash execution. When a peer already has a session ID, any change remains a hard failure. When the ID is initially null, the wrapper rechecks that it is still null immediately before prompting and requires a non-null ID afterward. Read-only `resolve` and `read` operations accept a concurrent null-to-initialized transition after the identity checks. If post-prompt initialization fails, the prompt has already been delivered and must not be retried automatically. Atomic protection against replacement during either path requires Herdr to compare an expected agent session ID or pane-occupant generation inside the socket operation that submits the prompt.
