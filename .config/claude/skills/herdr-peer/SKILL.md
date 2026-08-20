---
name: herdr-peer
description: Safely consult the opposite Claude or Codex agent in the same Herdr tab through the guarded herdr-peer command. Use when the user explicitly asks Claude and Codex to collaborate, asks one agent to consult or review with the other, or invokes herdr-peer. When invoked without an additional task, default to a read-only review of the current task's edits, including known non-sensitive gitignored edits. If fixes are authorized, batch the confirmed fixes and run delta-scoped re-reviews within a bounded number of rounds (one initial review plus at most two follow-ups), then report any unresolved findings to the user; otherwise report findings and stop without editing. Do not use for implicit delegation or ordinary background work.
---

# Herdr Peer

Use `herdr-peer`; never call raw Herdr input commands directly. The wrapper resolves exactly one opposite agent in the current tab and rechecks self-targeting, ambiguity, readiness, and agent-session replacement immediately before sending. A newly opened agent may not have a native session ID until its first prompt; the wrapper permits only that null-to-initialized transition while keeping the pane, tab, workspace, agent-kind, and readiness checks in place. Empty or non-string session IDs are invalid rather than uninitialized.

## Default review scope

When invoked without an additional task or review scope, request a read-only review of the edits made for the current task.

- Build a self-contained request that accounts for every path known to have been edited or created for the task, including staged, unstaged, untracked, and gitignored paths, subject to the sensitive-content rule below. Include the task intent, known constraints, and tests already run.
- Use the current conversation and tool history to identify gitignored edits; `git status` and `git diff` do not enumerate them. For each ignored path, state whether it was created or modified and give enough task intent for a meaningful review.
- Ask the peer to review the declared scope comprehensively in this single response: label every finding with a stable ID (F1, F2, ...), a severity of blocker, major, minor, or nit, and file and line references, and explicitly list any part of the scope it could not examine and why. State that later rounds only verify fixes. If no findings exist, ask the peer to say so explicitly.
- Do not scan or include every ignored file. Include only ignored paths known to have been edited for the current task.
- For any edited file that may contain credentials or other secrets, do not ask the peer to open it and do not include its raw contents. Provide a redacted diff or summary with all secret values removed when that permits a meaningful review; otherwise exclude the contents and report the resulting review limitation. Treat the path itself as sensitive when applicable.
- If no task-local edited paths are known, fall back to the current staged, unstaged, and untracked working-tree changes and state that no known gitignored edit was identified.

## Severity and loop policy

Severities: blocker means the change is unsafe or cannot be completed or shipped as is; major means a substantive defect in intended behavior that requires correction; minor means a concrete but non-blocking defect; nit means style or preference. Only a loop-blocking finding extends the review loop: a blocker- or major-severity finding concerning correctness, security, privacy, data integrity, specification non-conformance, build or test failure, compatibility, or a serious operational failure. Minor and nit findings are reported to the user once and are neither auto-fixed nor re-reviewed unless the user asks.

The loop is bounded to one initial review plus at most two follow-up reviews. Reaching the cap is not a pass: report the unresolved loop-blocking findings, disagreements, and unexamined areas to the user, and start further rounds only on the user's explicit instruction. A timeout or incomplete peer response is never treated as a zero-finding result; it consumes the round and, per the wrapper's delivery semantics, must not be auto-resent.

## Review loop

After receiving findings, verify each one against the local files before changing anything. When the current task authorizes a fix, verify all loop-blocking findings locally, apply the confirmed fixes together as one batch, run the relevant tests, and request a single delta-scoped follow-up review covering every loop-blocking disposition — fixes and rejected-with-evidence decisions alike. Without authorization to fix, report the findings and stop; do not repeatedly review unchanged files.

- Maintain a finding ledger across rounds: each finding keeps its stable ID, its disposition (fixed, rejected with evidence, or deferred), and the hunks that address it. Include the ledger in every follow-up request so resolved items are not re-raised and scope does not drift.
- Scope each follow-up to the delta: the fixed hunks, the rejected-with-evidence decisions, the interfaces, callers, tests, and invariants they directly affect, and any regression the fixes may have introduced. Findings causally introduced by the delta may be raised at any severity and get new IDs; minor and nit ones are reported once without extending the loop. Instruct the peer not to re-review unchanged code; an issue outside the delta may be reported only when it is a severe security or data-loss problem.
- Record the peer identity from the initial resolution. Before every follow-up, make a best-effort comparison of the tab, workspace, pane, agent kind, and session ID; allow only the initial null-to-initialized session transition when all other identity fields still match. Stop on a detected replacement instead of continuing with a different agent. This comparison is not atomic with the later prompt submission.
- Finish when the local agent has no unresolved loop-blocking finding and the peer explicitly reports that no blocker or major finding remains unresolved for the listed findings — including rejected-with-evidence dispositions — and their impact scope. Report that agreement to the user; do not infer it from silence or a partial response.
- If the agents disagree, compare concrete file and line evidence and continue only when the resolution is supported by the repository. Do not change code merely to mirror the peer's opinion.
- Stop and report the blocker instead of claiming agreement when progress requires new user authority, the peer cannot be reached safely, the round cap is hit, or the disagreement cannot be resolved from available evidence.

## Workflow

1. Confirm the selected peer without changing state:

   ```bash
   herdr-peer resolve
   ```

2. Send one complete, self-contained request and wait for the peer to settle:

   ```bash
   herdr-peer prompt "Read-only review, round 1 of at most 3. Task intent: INTENT. Constraints: CONSTRAINTS_OR_NONE. Tests already run: TESTS_OR_NONE. Review these edited paths: PATHS. Known non-sensitive gitignored edits: PATHS_OR_NONE. Sensitive edits omitted or redacted: SUMMARY_OR_NONE. Review the declared scope comprehensively in this single response: label every finding F1, F2, ... with severity blocker/major/minor/nit and file:line references, and explicitly list any part of the scope you could not examine and why. Later rounds only verify fixes. Say explicitly if no findings exist."
   ```

   Replace the uppercase placeholders with task-specific values before sending.

   Use `--timeout <milliseconds>` before the quoted prompt only when the default five minutes is unsuitable.

3. Read the peer's response:

   ```bash
   herdr-peer read
   ```

   Use `--lines <count>` when more context is needed.

4. Integrate the result. If the round produced loop-blocking findings and fixing is authorized, verify them, batch the fixes, then repeat steps 1–3 once per follow-up round using the delta template:

   ```bash
   herdr-peer prompt "Read-only delta re-review, round N of at most 3. Finding ledger with dispositions (fixed / rejected with evidence / deferred): LEDGER. Changed since last review: PATHS_AND_HUNKS. Constraints still in effect: CONSTRAINTS_OR_NONE. Tests run after the fixes: TESTS_OR_NONE. Sensitive delta content omitted or redacted: SUMMARY_OR_NONE. Verify the listed dispositions — the fixes and the rejected-with-evidence decisions — plus the interfaces, callers, tests, and invariants they directly affect, and any regression they introduced. Findings caused by these changes may be raised at any severity; give them new IDs continuing from LAST_ID. Do not re-review unchanged code; report an issue outside this delta only if it is a severe security or data-loss problem. List any part of this delta or impact scope you could not examine and why. Say explicitly whether any blocker or major finding remains unresolved."
   ```

   If the peer becomes `blocked` or the command times out, inspect with `herdr-peer read` and report the blocker instead of guessing.

## Coordination rules

- Send only when the user explicitly requested Claude/Codex collaboration.
- Keep the peer request self-contained and state whether it is read-only or may edit files.
- Do not invoke this skill in response to a peer-originated prompt; return the result to the caller and prevent delegation loops.
- Do not bypass `herdr-peer` with raw Herdr prompt or pane-input commands.
- Treat resolution or validation failure as a hard stop. Do not select another tab, workspace, or agent manually.

The deterministic wrapper is installed from `scripts/herdr-peer` as the `herdr-peer` command. Its recheck and the shared command hook are best-effort guardrails, not a security boundary for arbitrary Bash execution. When a peer already has a session ID, any change remains a hard failure. When the ID is initially null, the wrapper rechecks that it is still null immediately before prompting and requires a non-null ID afterward. Read-only `resolve` and `read` operations accept a concurrent null-to-initialized transition after the identity checks. If post-prompt initialization fails, the prompt has already been delivered and must not be retried automatically. Atomic protection against replacement during either path requires Herdr to compare an expected agent session ID or pane-occupant generation inside the socket operation that submits the prompt.
