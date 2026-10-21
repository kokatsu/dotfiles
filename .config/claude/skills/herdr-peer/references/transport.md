# Herdr transport and saved results

Read before sending a peer request or interpreting a wrapper verdict. Use [task templates](tasks.md) for the request body and receiver result contract. This workflow uses the existing CLI; file preparation, execution records, and result checks are the caller's responsibility.

## Resolve and prepare

1. Run `herdr-peer resolve` to select the sole opposite agent in the current tab. Respect the adapter's sandbox and approval requirements for every CLI invocation.
2. Verify both panes share one local Git worktree, and the peer's canonical `cwd` equals its canonical Git root. Compare that root with the caller's canonical Git root. Different worktrees, subdirectory peer cwd, remote machines, and containers are outside this workflow. Matching Herdr workspace IDs alone does not prove filesystem sharing.
3. Check that `<git-root>/.kokatsu/herdr-peer/` resolves inside the shared root, including any existing symlink components. Verify the prospective result paths are ignored with `git check-ignore`. Stop on missing ignore rules or an unsuitable path; do not silently change ignore rules or choose a different destination.
4. Use `umask 077`, create the parent directory, and create a fresh task directory with `mktemp -d` under that parent. Its generated basename is `task_id`. Check the resolved directory remains inside the shared root. Do not reuse or overwrite a prior task directory.
5. Save the resolved peer JSON as `peer.json` and the assembled prompt body as `request.md`. Keep the initial identity for later calls; a fresh resolution alone does not detect replacement between invocations. Immediately before sending, compare a new resolution with the recorded pane, tab, workspace, agent kind, and session ID. Allow only an initial null-to-initialized session transition when all other fields match; record the initialized ID for later comparisons.

Each request, including a delta review or retrieval-only request, gets its own directory:

```text
<git-root>/.kokatsu/herdr-peer/<task_id>/
  request.md       Caller: exact assembled prompt body before wrapper additions
  peer.json        Caller: resolved peer identity, including cwd and session ID
  execution.md     Caller: tool handle, execution state, exit code when known
  transport.out    Caller: raw prompt stdout, ending in the wrapper verdict
  transport.err    Caller: prompt stderr
  result.tmp.md    Peer: temporary result and initial write-access check
  result.md        Peer: full answer, moved into place with shell mv
  recovery.md      Caller: later observations and completion checks, if needed
```

`request.md` is a caller record; send its full contents as the prompt argument. The peer need not read it. Include the absolute result paths and receiver contract in that body. The peer checks its cwd and ability to create `result.tmp.md` before product work; path validation by the caller does not prove write access inside the peer's sandbox.

Only the caller writes request, peer, execution, transport, and recovery records. Only the peer writes the two result files. Result directories have no automatic retention or cleanup: they remain until explicitly deleted. Move durable conclusions into user-requested tracked documentation separately.

## Send once and track execution

Options go after the subcommand. Use the installed `herdr-peer` command, with the exact contents of `request.md` passed as one quoted argument. For example, after setting `task_dir` to the prepared absolute path and loading `request_body` from the file:

```bash
herdr-peer prompt --timeout 1800000 -- "$request_body" >"$task_dir/transport.out" 2>"$task_dir/transport.err"
```

This command must be launched through the caller's execution mechanism below; do not paste it into a foreground call whose execution limit is shorter than the CLI budget. Preserve literal request content when constructing shell arguments; do not interpolate prompt text as executable shell code.

| Task | Starting CLI budget |
| --- | --- |
| Research | `--timeout 600000` (10 minutes) |
| Implementation | `--timeout 1800000` (30 minutes) |
| Initial or delta review | `--timeout 900000` (15 minutes) |
| Retrieval only | `--timeout 600000` (10 minutes) |

These are adjustable starting values, not measured completion guarantees. The CLI default remains five minutes. One budget covers resolution, delivery, and completion checks; the send receives what remains. The clock has one-second granularity and a single Herdr call is not interrupted mid-flight, so the budget is approximate rather than a hard deadline. An exhausted budget before the send reports that nothing was delivered.

- **Claude:** Check the active Bash tool definition and use `run_in_background: true` for all task types above so the CLI budget does not depend on the foreground execution limit. Redirect both streams from launch as shown and retain the returned task handle. If the tool specifies completion notifications, wait for that notification without polling the output files or task-output facility; after notification, collect the exit status and saved output as permitted by that tool. Follow the active definition rather than assuming every Claude environment behaves identically. Do not append shell `&` or detach the process instead.
- **Codex:** Check the active execution tools. With `exec_command` / `write_stdin`, retain a returned `session_id` and resume that execution with `write_stdin`; an elapsed `yield_time_ms` is not process termination. If `functions.exec` yields a running cell, resume that cell with its wait tool first to retrieve the underlying result. Preserve applicable socket escalation requirements. Do not assume Claude's timeout parameters apply to Codex.
- Record tool handles and state transitions in `execution.md`, including the exit code once available. If execution finishes before a handle is needed, record that outcome. If the caller lacks a supported way to keep and observe a long-running execution, stop before sending and report the limitation.

Wait for the original process to exit before interpreting its final verdict. A tool returning early is not grounds to launch another prompt. A forced termination or lost handle leaves process state and delivery uncertain; do not assume the peer stopped or that an exit trap wrote a verdict. Keep logs, do not resend, and report the uncertainty. A normal nonzero exit must also preserve all artifacts and proceed to verdict inspection rather than aborting the caller's workflow without reporting.

## Interpret the verdict and read the result

The wrapper appends a unique completion marker to the prompt and asks the peer to end its terminal reply with that marker on its own line. After delivery, including delivery-unknown exits that run its exit trap, the wrapper emits a final JSON line with `type: herdr_peer_prompt`, `completion`, `readiness`, `session`, `marker`, and `full_answer_capture`. Earlier stdout is raw Herdr output; do not assume the entire file is JSON Lines. Forced termination or output-write failure may leave no verdict.

- `completion: confirmed` means the reply's terminal marker was observed. Herdr's own exit code reports delivery, not reply completion: `agent prompt --wait` can return while a long reply is still streaming, and the agent can report `idle` throughout.
- `session` is `initialized`, `uninitialized`, or `changed`. Neither of the latter invalidates an already confirmed reply, because its unique marker is stronger evidence than the reported session ID. Report either value to the user. `changed` counts as replacement before another request and blocks the timeout-recovery procedure below.
- `readiness` concerns the next operation. A confirmed reply with unconfirmed readiness is still a confirmed reply. Before another request or conflicting edit, re-resolve the same peer and observe `idle` / `done` twice at least one second apart; do not send into a post-answer hook still running.
- `full_answer_capture` remains `unverified`: the terminal window may contain the reply's tail without its head. Independently read `result.md`, match its task ID, kind, final `HERDRPEERRESULTEND:<task_id>` line, and required sections, then inspect the actual answer and limitations. Do not count `result.tmp.md` as final.

Exit code 0 with markers enabled means the wrapper saw the terminal marker; it does not prove result saving or task success. With `--no-marker`, even exit code 0 makes no completion claim. The task-file workflow requires markers; do not use `--no-marker` for these requests.

For a nonzero exit after delivery or uncertain delivery, inspect the verdict and logs; never automatically resend. The wrapper still checks the marker after Herdr's `agent_prompt_stalled` or `timeout` errors, since neither means the prompt went unsent. Other send errors stop with delivery unknown. A failure explicitly stating nothing was delivered, such as an exhausted pre-send budget or failed pre-send validation, may be retried after fixing the condition. `blocked` stops waiting because a person is needed, not because the task succeeded.

| Evidence | Caller action |
| --- | --- |
| Confirmed terminal marker and valid result file | Read the full file; verify task-specific claims separately |
| Confirmed terminal marker but absent or invalid result file | Report saving failure; retrieval-only may recover the previous answer |
| Unconfirmed terminal marker but a result file exists | Treat as intermediate evidence; do not infer completion or resume conflicting editing |
| Timeout with original process exited | Use saved-marker observation below without sending again |
| Missing verdict, unreadable marker, lost process handle, or replaced peer | Report unconfirmed state, retain artifacts, and stop automatic continuation |

Check the implementation diff and reported commands, or review findings and their evidence, before adopting the result. Follow the canonical skill's review loop using the [delta template](tasks.md#delta-review) when appropriate. A partial or unconfirmed reply is never a zero-finding result or peer agreement.

## Observe completion after timeout

This procedure uses only `resolve` and `read`, never another `prompt`. It applies after the original process has exited with a saved marker and unconfirmed completion. Keep the original verdict unchanged.

1. Verify the last line of `transport.out` is a verdict with `type: herdr_peer_prompt` and a nonempty `marker`. Stop and report if the verdict or marker is unavailable; do not reconstruct one from unrelated text.
2. Start one five-minute observation budget. Re-resolve and compare the peer against `peer.json` and any recorded initial session initialization. Require the same pane, tab, workspace, and kind; allow only the initial null-to-initialized session transition. Stop on replacement or a saved verdict with `session: changed`. Herdr has misattributed Codex session IDs; this conservative stop can reject an unchanged peer, but avoids continuing with an uncertain occupant.
3. Read with `herdr-peer read --source visible --lines 1000`. If idle or done, `recent-unwrapped` is also available. Match the saved marker as the entire line after trimming surrounding whitespace, never as a substring in the echoed request. Recheck identity around reads; comparisons are best effort, not atomic with socket reads.
4. If absent, observe at intervals of at least two seconds, rechecking identity. Stop on `blocked`, replacement, or exhaustion of the five-minute observation budget. Do not send any prompt.
5. If present, read and validate `result.md` separately. Record the timestamp, peer identity, read source, marker evidence, and result checks in `recovery.md`. Report completion confirmed by a later read, without rewriting the original `completion: unconfirmed` verdict.
6. Before another request or conflicting edit, observe the same peer as `idle` / `done` twice at least one second apart. Include this readiness check in the same five-minute budget, starting at step 2. If it does not settle in that budget, report reply completion and next-operation readiness separately.

Missing screen history cannot be repaired by assuming a result-file footer, `status: completed`, or an idle pane proves reply completion. Preserve the unconfirmed state and editing hold, and report it when observation cannot settle it.

## Retrieval only

`read` defaults to `recent-unwrapped`; `--lines COUNT` and `--source visible|recent|recent-unwrapped|detection` select the window. Larger reads can fail with `agent_not_idle` while working or blocked; `visible` is still usable. Historically idle Codex reads have returned about 20–400 rows regardless of a larger requested count. Successive windows are not supersets. A screen read is observation, not a reliable full-answer archive.

If a confirmed reply did not produce a usable result file, first verify the same peer identity and readiness. Then prepare a fresh ignored task directory and request using the common fields and receiver result contract from [tasks.md](tasks.md). Keep the original task kind, reference its task ID, and use the fresh directory's ID for the retrieved result. Set `Allowed product edit paths` to `none`, even when the original task was implementation; do not carry its product edit authorization into retrieval. Replace the task instructions with:

```text
Retrieval only, not a new review round. Original task ID: ORIGINAL_TASK_ID.
Do not re-investigate, re-review, or resume implementation. Save the full previous
answer in the specified result format, retaining its substance and adding this
retrieval task's ID and end record. Only result.tmp.md and result.md in the new
directory may be created or changed. If the previous answer cannot be recovered,
return a blocked result explaining that limitation instead of reconstructing it
through new work. Follow the supplied result contract and terminal marker.
```

Observe and validate this request like any other single send. Retrieval does not consume a review round and never authorizes more product edits. If the original reply remains unconfirmed, do not send a retrieval prompt into a possibly still-running peer.

## Identity and transport limits

The wrapper and shared command hook are best-effort guardrails, not a security boundary for arbitrary Bash execution. Before sending, the wrapper requires an initially null session ID to remain null, while the caller may record an earlier null-to-initialized transition before invoking it. During post-delivery observation it records session changes instead of invalidating a confirmed marker. Read-only `resolve` and `read` also accept concurrent null-to-initialized transitions.

The wrapper holds no state between calls, so the caller must compare the original identity before follow-ups, retrieval, and recovery. Atomic protection against replacement requires Herdr to compare an expected session ID or occupant generation inside its socket operation. Keep each request self-contained and report detected replacement rather than selecting another pane or tab manually.
