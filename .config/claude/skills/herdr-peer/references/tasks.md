# Herdr peer task templates

Use these with [transport and saved results](transport.md). The caller assembles one request from the common fields, one task template, and the receiver result contract below. Replace placeholders with concrete values or an explicit `none`; send all three parts as the prompt body. Keep the request self-contained even if the peer restarts between calls.

## Common fields

```text
Task ID: TASK_ID
Kind: research | implement | review
Goal and acceptance criteria: GOAL
Background: BACKGROUND
Shared canonical Git root: GIT_ROOT
Read/review scope: PATHS_AND_INTERFACES
Allowed product edit paths: PATHS_OR_NONE
Excluded paths and actions: EXCLUSIONS
Constraints and user authorization: CONSTRAINTS
Current task changes (staged, unstaged, untracked): CHANGES_OR_NONE
Known non-sensitive gitignored task edits (created/modified): IGNORED_EDITS_OR_NONE
Sensitive material omitted or redacted: SUMMARY_OR_NONE
Verification already performed and results: TESTS_OR_NONE
Result directory: ABSOLUTE_TASK_DIRECTORY
Result file: ABSOLUTE_RESULT_MD
Temporary result file: ABSOLUTE_RESULT_TMP_MD
```

Do not scan all ignored files. Include only known task edits, and exclude the communication artifacts themselves from the product change scope. For sensitive paths, supply redacted evidence or report the omitted scope without asking the peer to read the secrets. Account for the existing default review scope in the canonical skill when filling these fields.

## Research

```text
Research the stated question within the read scope. Do not edit product files.
Explain your conclusion with file and line evidence or other sources you actually
checked. Trace relevant callers and constraints. Compare alternatives when useful,
give a reason for your recommendation, and separate confirmed facts from unknowns.
State what you could not investigate and why. Result artifacts are the only files
you may create or modify. Do not delegate to another agent.
```

## Implementation

```text
Implement the stated goal only in the allowed product edit paths, within the
user authorization and constraints above. Preserve unrelated existing changes.
Run checks appropriate to the change and report the exact commands and results.
If another file, new authority, or a conflicting edit is needed, stop and return
a blocked or partial result; do not expand the assignment. List all paths you
created or modified, why they changed, remaining work, and verification limits.
Do not commit, push, deploy, apply environment configuration, or delegate to
another agent. Result artifacts are also authorized as specified below.
```

The caller keeps the assigned paths stable until completion and readiness are confirmed. If other files must remain stable for the implementation, pause local editing too. Validate the resulting diff and reported checks before adopting the peer's conclusion.

## Initial review

```text
Read-only review, round 1 of at most 3. Review the declared current-task changes
comprehensively, including the interfaces, callers, tests, and invariants they
directly affect. Label every finding with a stable ID (F1, F2, ...), severity
blocker/major/minor/nit, file and line references, the failure symptom, and evidence.
Explicitly list any part of the scope you could not examine and why. Say explicitly
if no findings exist and whether any blocker or major finding remains unresolved.
Later rounds only verify fixes and rejected-with-evidence dispositions. Do not fix
reviewed files. Result artifacts are the only files you may create or modify.
Do not delegate to another agent.
```

## Delta review

Use a fresh task directory and task ID. Fill these additional fields and include the delta instructions instead of the initial review instructions:

```text
Parent task ID and result path: PARENT_ID_AND_RESULT
Round: N of at most 3
Finding ledger (fixed / rejected with evidence / deferred): LEDGER
Changed since last review: PATHS_AND_HUNKS
Checks after the fixes and results: TESTS_OR_NONE
Last finding ID: LAST_ID

Read-only delta re-review. Verify the listed dispositions, including fixes and
rejected-with-evidence decisions, plus the interfaces, callers, tests, and
invariants they directly affect and any regression they introduced. Findings caused
by these changes may be raised at any severity; give them new IDs continuing from
the last ID. Do not re-review unchanged code. Report an issue outside this delta
only if it is a severe security or data-loss problem. List unexamined delta or
impact scope and why. Say explicitly whether any blocker or major remains
unresolved. Do not edit product files or delegate to another agent. Only the
specified result artifacts may be written.
```

Apply the canonical skill's severity and loop policy: minor and nit findings do not extend the loop; at most two delta reviews follow the initial review. Retrieval-only requests are not review rounds and do not authorize re-investigation.

## Receiver result contract

Append these instructions to every request, filling in the same task ID, kind, and absolute paths used in the common fields. The peer must receive this contract in the prompt, not just a link to this reference.

```text
Before product work, confirm that the shared Git root is your canonical cwd and
that you can create the specified temporary result file. If either check fails,
do not edit product files; report the reason in the terminal. Do not change ignore
rules, permissions, or working directories to get around the failure.

You may create and write only the specified result.tmp.md and result.md as result
artifacts, in addition to any explicitly authorized product edit paths. The request,
peer identity, execution, transport, and recovery records belong to the caller;
leave them untouched. The prompt body is the full request; request.md is only the
caller's record and does not need to be read.

Write the full result in the user's language using the result schema below. Fill
the task ID and kind exactly, select completed/blocked/partial, and replace the
section guidance with your actual answer. Include the selected task's required
content. Report limitations explicitly, including none when appropriate.

Write the whole result to the specified result.tmp.md, then use shell mv to move it
to the specified result.md in the same directory. Do not use a patch tool's move
operation. If result.md already exists, do not overwrite it; report the conflict.
If saving fails, report the failure instead of claiming success. After saving,
do not modify the result again or perform more product work for this request.

Reply in the terminal with the absolute result path, status, and a short summary,
followed by the separate final completion marker requested by the wrapper. The
result-file end record below does not replace that terminal completion marker.
```

Include this schema after the contract, filling the task ID and kind before sending:

```markdown
# Result

task_id: TASK_ID
kind: KIND
status: completed | blocked | partial

## Outcome

Research: conclusion, checked evidence, relevant alternatives and recommendation.
Implementation: changed paths and reasons, acceptance criteria, remaining work.
Review: stable finding IDs, severity, file:line, symptoms and evidence; explicitly
state no findings when applicable and whether any blocker or major remains.

## Verification

Sources actually checked; commands actually run and their results. Do not label
unperformed checks as successful.

## Limitations

Unexamined scope, incomplete work, or decisions needed; explicitly state none if so.

HERDRPEERRESULTEND:TASK_ID
```

`completed` is the peer's report, not proof of correct code, successful tests, or zero findings. The caller checks the file and task outcome separately from transport completion. Keep partial work and saved results when blocked; never restart the original assignment just to retrieve its answer.
