---
name: bug-hunt
description: Statically investigate latent bugs in existing code. Use on "bug hunt", "latent bugs", "code audit".
argument-hint: "<file path, directory, or feature name>"
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(git show *)
  - Bash(bash ${CLAUDE_SKILL_DIR}/*)
  - Bash(mkdir -p */.kokatsu/*)
  - Bash(git rev-parse --show-toplevel)
  - Write
---

# Bug Hunt — Latent Bug Investigation

A skill for discovering hidden bugs in existing code through code reading and pattern matching.
Proactively searches for **undiscovered latent bugs**.

**Respond to the user in the same language they use.**

## Arguments

- `$ARGUMENTS`: Investigation target (optional)
  - File path: `/bug-hunt src/controllers/users_controller.rb`
  - Directory: `/bug-hunt src/`
  - Feature name: `/bug-hunt payment processing`
  - If omitted: Target diff files on the current branch

## Procedure

### 1. Identify and Analyze Target

**When the argument is a file/directory:**

Run the `analyze` script, then read the files. Multiple paths are supported:

```bash
bash ${CLAUDE_SKILL_DIR}/analyze <path1> [path2] [path3] ...
```

**When the argument is a feature name:**

- Identify related files using Grep / Glob
- Run `analyze` on the identified files

**When the argument is omitted:**

Run both scripts to identify targets and prioritize:

```bash
bash ${CLAUDE_SKILL_DIR}/analyze --diff
bash ${CLAUDE_SKILL_DIR}/hotspots
```

The `analyze --diff` auto-detects the main branch and gathers diff file stats.
The `hotspots` output highlights high-churn files worth investigating.
Lock files, build output, tests, and i18n files are excluded by default.
If `analyze` reports 0 files, select investigation targets from hotspots using the criteria below.

#### Hotspot Target Selection Criteria

1. **Skip auto-generated files** — check CLAUDE.md for project-specific auto-generated file patterns. These should not be investigation targets
2. **Prioritize business logic** — workers, models, services, controllers over views/config
3. **Select parallel implementations as a set** — if one platform-specific module is a hotspot (e.g., `storage_backend`), also include its siblings. Cross-implementation comparison catches pattern inconsistencies
4. **Aim for 3,000–10,000 total lines** — enough depth for meaningful findings without overwhelming agents
5. **Run `analyze` on the selected files** to get the correct strategy:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/analyze file1.rb file2.rs file3.ts ...
   ```

### 2. Bug Investigation

#### Scale-Based Strategy

Use the `strategy` field from `analyze` output:

| `strategy` value | Action |
|------------------|--------|
| `direct` | Investigate directly (no sub-agents). Cover all perspectives (A+B+C) yourself |
| `3-agent` | Launch **3 Explore agents** in parallel, one per perspective |

#### 3-Agent Configuration

Launch 3 agents (subagent_type: Explore) **in parallel**.
Pass each agent the list of target file paths and its investigation perspective.
**Each agent reports only its assigned perspective** (ignore findings from other perspectives).

#### Agent Perspectives

Read `${CLAUDE_SKILL_DIR}/perspectives.md` for the common instructions and the 3 investigation perspectives (A: Data Safety, B: Control Flow, C: Security).
Include the common instructions and the assigned perspective in each agent's prompt.

### 3. Result Integration and Report Output

#### Verification (Required)

Do not adopt agent reports as-is. Verify all findings, prioritizing Critical / High:

1. **Read the reported file:line** directly to confirm the evidence
2. **"X doesn't exist" / "X and Y don't match" claims**: Check related docs and configs to rule out intentional changes
3. **Duplicate findings across agents**: Merge into one, adopting the most accurate analysis
4. **Reproduction conditions**: Trace code paths to confirm reported conditions can actually occur

Exclude findings whose evidence cannot be confirmed.

#### Existing Report Deduplication

Before writing the report, check the output directory for existing bug-hunt reports:

1. Glob for `bug-hunt-*.md` in the output directory
2. If recent reports exist (same date or within the past week), **read their findings**
3. Exclude any finding that is already reported in an existing report
4. In the new report, add a "Cross-Reference" section listing which existing reports were checked

#### Report Output Directory

Save reports to `.kokatsu/bug-hunt/` under the Git repository root.
Determine the root with `git rev-parse --show-toplevel` and create the directory if needed:

```bash
mkdir -p "$(git rev-parse --show-toplevel)/.kokatsu/bug-hunt"
```

Use the absolute path for the report file as well.

#### Report File Naming

- Format: `bug-hunt-YYYY-MM-DD-HHmm.md`
- When a target descriptor helps identify the scope, append it:
  - `bug-hunt-YYYY-MM-DD-HHmm-payment-workers.md`
  - `bug-hunt-YYYY-MM-DD-HHmm-auth-module.md`

#### Report Format

See `${CLAUDE_SKILL_DIR}/REPORT_TEMPLATE.md` for the output format and severity criteria.

## Notes

- **Reduce false positives**: Do not report based solely on "it could happen."
  Show cases where it actually becomes a problem
- **Specify reproduction conditions**: Describe what input or state causes the issue to manifest
- **Check existing defenses**: Do not flag as a bug if the framework already prevents it
  (e.g., Rails CSRF protection)
- **Do not blindly trust agent reports**: Important findings must include evidence (file path:line number)
