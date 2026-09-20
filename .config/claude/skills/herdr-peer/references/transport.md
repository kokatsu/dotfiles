# Herdr transport and request templates

Read before sending a peer request or interpreting a wrapper verdict.

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

   Use `--timeout <milliseconds>` before the quoted prompt only when the default five minutes is unsuitable. One budget covers resolution, delivery and the completion check together, so the send receives what is left rather than the full amount again. The clock has one-second granularity and a single herdr call is never interrupted mid-flight, so treat the budget as approximate rather than a hard ceiling. The deadline is the current whole second plus your timeout rounded up to whole seconds, so the real budget lands within a second below that rounded value and can be either shorter or longer than what you asked for. A timeout near a second can therefore be spent resolving the peer and stop before the send; that failure reports that nothing was delivered and may be retried. Several seconds leaves the rounding a small fraction of the whole, though no budget outlasts a resolution slower than itself.

   The wrapper appends a per-request completion marker to whatever you send and asks the peer to end its reply with that marker on its own line. It then prints a second JSON line reporting what it could confirm: `completion`, `readiness`, and `full_answer_capture`. A `completion` of `confirmed` is the only evidence that the reply finished. Herdr's own exit code reports delivery, not completion; `agent prompt --wait` returns while a long reply is still streaming, and the peer's status can read `idle` throughout.

   `--no-marker` sends the prompt unchanged for cases where the appended sentence would break a strict output format. The verdict then reports `completion` as `unconfirmed`, and nothing else may be used to infer that the reply finished — a still screen does not mean a finished reply, because the peer may be thinking or waiting on a tool.

   With the marker in play, exit code 0 means the wrapper saw the reply's terminal marker — nothing more. It does not mean the whole reply is still on screen; check that separately, as `full_answer_capture: "unverified"` says. Under `--no-marker` exit code 0 carries no completion claim at all, since `completion` stays `unconfirmed`. Any non-zero exit after the send means the prompt was delivered, or its delivery is unknown, which is treated the same way: inspect with `herdr-peer read` and report; never resend. A non-zero exit that says nothing was delivered — an exhausted budget before the send, or a failed identity check — may be retried. The verdict line is printed on those failures too, including when the peer is replaced mid-poll, so read it rather than assuming nothing came back. A peer that goes `blocked` while the reply is pending ends the wait immediately instead of burning the budget, because it is waiting on a person.

   `readiness` is about the *next* send, not this reply. `completion: confirmed` with `readiness: unconfirmed` still exits 0 and the reply is trustworthy; it only means the peer had not settled yet. Run `herdr-peer resolve` and wait for `idle` or `done` before the next round rather than sending into a peer that is still running its post-answer hook.

3. Read the peer's response:

   ```bash
   herdr-peer read
   ```

   Use `--lines <count>` when more context is needed.

   A confirmed marker proves the reply's tail arrived, not that you can still see its head. The pane read returns a bounded window (about 1000 rows on herdr 0.9.0) shared with whatever preceded the reply, so a long reply loses its beginning. `full_answer_capture` is always reported as `unverified` for that reason. Dump the read to a file the moment the verdict lands and check both ends; successive reads return different windows, not supersets. When the head is gone, ask the peer to re-emit the missing part. That is retrieval, not a review round, so do not count it against the round cap.

4. Integrate the result. If the round produced loop-blocking findings and fixing is authorized, verify them, batch the fixes, then repeat steps 1–3 once per follow-up round using the delta template:

   ```bash
   herdr-peer prompt "Read-only delta re-review, round N of at most 3. Finding ledger with dispositions (fixed / rejected with evidence / deferred): LEDGER. Changed since last review: PATHS_AND_HUNKS. Constraints still in effect: CONSTRAINTS_OR_NONE. Tests run after the fixes: TESTS_OR_NONE. Sensitive delta content omitted or redacted: SUMMARY_OR_NONE. Verify the listed dispositions — the fixes and the rejected-with-evidence decisions — plus the interfaces, callers, tests, and invariants they directly affect, and any regression they introduced. Findings caused by these changes may be raised at any severity; give them new IDs continuing from LAST_ID. Do not re-review unchanged code; report an issue outside this delta only if it is a severe security or data-loss problem. List any part of this delta or impact scope you could not examine and why. Say explicitly whether any blocker or major finding remains unresolved."
   ```

   If the peer becomes `blocked`, the command times out, or the verdict reports `completion` as `unconfirmed`, inspect with `herdr-peer read` and report the blocker instead of guessing. An unconfirmed or partial reply is never a zero-finding result and never counts as the peer's agreement, no matter how complete the visible text looks.

The deterministic wrapper is installed from `scripts/herdr-peer` as the `herdr-peer` command. Its recheck and the shared command hook are best-effort guardrails, not a security boundary for arbitrary Bash execution. When a peer already has a session ID, any change remains a hard failure. When the ID is initially null, the wrapper rechecks that it is still null immediately before prompting and requires a non-null ID afterward. Read-only `resolve` and `read` operations accept a concurrent null-to-initialized transition after the identity checks. If post-prompt initialization fails, the prompt has already been delivered and must not be retried automatically. Atomic protection against replacement during either path requires Herdr to compare an expected agent session ID or pane-occupant generation inside the socket operation that submits the prompt.

After delivery the wrapper only observes: it polls the pane for the completion marker and rechecks the pane, tab, workspace, agent kind, and session ID on every poll. Reading repeatedly is not resending, so this does not weaken the single-send rule. Once the marker lands it waits for a short `idle` or `done` streak, because the peer runs hooks after answering and would otherwise trip the pre-send readiness guard on the next round; that guard still runs before the next send. Every failure in this phase reports that the prompt was delivered and forbids an automatic retry, including a peer replaced mid-poll.

The wrapper holds no state between invocations, so it cannot see a peer that was replaced between two of your calls. Comparing against the identity you recorded at the initial resolution is the caller's job, and the replacement only surfaces in the response after the prompt has landed. Keep every request self-contained so a silent peer restart does not invalidate it.
