# Agent Investigation Perspectives

## Common Instructions for All Agents

Include the following in each agent's prompt:

> **Pre-investigation: Read project documentation first.**
> Before reading target files, check for `CLAUDE.md` and `README.md` in the target directory and its parent directories.
> Note any documented design decisions, known limitations, and intentional trade-offs.
> Do not report documented behavior as bugs.
>
> **Cross-implementation comparison (when applicable):**
> If target files include parallel implementations for different platforms,
> compare error handling, retry strategies, and guard conditions across them.
> Pattern inconsistencies between parallel implementations are high-value findings.
>
> **Verification obligation when inconsistencies are found:**
> Before concluding "A and B don't match" or "X doesn't exist", always check:
>
> - Related documentation (README, docs/, ADR, etc.)
> - Infrastructure/deployment configs (CI/CD workflows, CDN settings, etc.)
> - Configuration files (config/, .env.example, etc.)
>
> Design changes or refactoring may cause intentional apparent inconsistencies.
> Do not declare something a "bug" without verification.
>
> **Self-check before reporting each finding:**
> Before including a finding in your report, verify:
>
> 1. Can the problematic code path actually be reached with real input?
>    - **For "unsafe pattern" findings** (SQL injection, dynamic dispatch, etc.): trace at least one level of callers using Grep to check whether user/external input can reach the parameter. If all callers pass hardcoded values, downgrade from Critical/High to Low (defense-in-depth).
>    - **For initialization/startup code**: check when it runs relative to the runtime lifecycle (e.g., before or after threads are spawned).
> 2. Does the framework or library already prevent this? (e.g., Rails CSRF, Rust borrow checker)
> 3. Is it documented as intentional? (check comments, CLAUDE.md, README)
>
> If you cannot confirm the finding after checking, **do not include it**.
> Never report a finding and then withdraw it — decide before reporting.
>
> **What is NOT a bug (do not report):**
>
> - Code style violations (e.g., println! instead of tracing, naming conventions)
> - Development-only behavior (e.g., placeholder URLs in development mode)
> - Missing documentation or comments
> - Code duplication that doesn't cause functional issues
> - Performance optimizations (unless they cause correctness issues)
>
> Focus exclusively on **functional bugs that affect production behavior**.
>
> **When a finding spans multiple perspectives:**
> Report it from ONE perspective only, using this priority: Data Safety > Control Flow > Security.
> Example: "API call error dropped AND control falls to wrong branch"
> → Agent A reports the data loss aspect. Agent B does NOT re-report the fall-through.

## Agent A: Data Safety

(Control flow and security perspectives are out of scope — do not report)

> **Scope boundary examples:**
>
> - "Undefined variable causes NameError" → YOUR scope (missing value)
> - "split result accessed at index [1] without length check" → YOUR scope (boundary value)
> - "S3/API error discarded, returns generic NotFound" → YOUR scope (error value lost)
> - "Error silently swallowed in rescue block" → NOT your scope (error handling = Agent B)
> - "Err branch falls through to wrong code path" → NOT your scope (branch coverage = Agent B)
> - "Missing timeout on API call" → NOT your scope (external integration = Agent C)

### Null / Undefined / Empty Values

- Method chaining without nil / null / undefined checks
- Unchecked references to Optional values
- First-element access on empty arrays/collections
- Unhandled cases where DB-fetched values can be nil

### Type Mismatches

- Unsafe casts or assertions that bypass type checking
- Implicit type conversions that may lose data
- Unchecked error return values
- Parameter type vs. actual value mismatches

### Boundary Values

- Out-of-bounds array access
- Date boundaries (month-end, year-end, timezone crossings)
- Pagination edges (0 items, last page)
- String length / numeric range upper bound checks
- Integer overflow

## Agent B: Control Flow & State Management

(Data safety and security perspectives are out of scope — do not report)

> **Scope boundary examples:**
>
> - "Same DB update called twice in error path" → YOUR scope (control flow duplication)
> - "Non-retryable errors still retried up to max count" → YOUR scope (missing branch)
> - "DB error returns Ok(()) instead of propagating" → YOUR scope (error handling)
> - "Undefined variable referenced" → NOT your scope (missing value = Agent A)
> - "Array index access without bounds check" → NOT your scope (boundary value = Agent A)
> - "No HTTP timeout on external API call" → NOT your scope (external integration = Agent C)

### Missing Branch Coverage

- Missing default / else in switch / case / match statements
- Patterns not covered in if-else chains
- Unconsidered state combinations in status transitions
- Unreachable code after early returns

### Error Handling

- Empty rescue / catch / except blocks (swallowed errors)
- Catching all exception types without distinction
- Missing resource cleanup on error (DB connections, file handles)
- Unhandled Promise / Future errors

### Concurrency & Race Conditions

- TOCTOU: Other processes can interleave between read and update
- Insufficient lock scope (missing required mutual exclusion)
- Non-atomic cache operations (non-atomic read-modify-write)
- Potential deadlocks (inconsistent lock acquisition order)

## Agent C: Security & External Integration

(Data safety and control flow perspectives are out of scope — do not report)

> **Scope boundary examples:**
>
> - "No HTTP timeout on API call" → YOUR scope (external integration)
> - "Retry doesn't consider idempotency" → YOUR scope (external integration)
> - "API credentials logged in plaintext" → YOUR scope (security)
> - "Err variant silently dropped" → NOT your scope (data safety = Agent A)
> - "Retry logic doesn't check is_retryable" → NOT your scope (control flow = Agent B)
> - "Double DB write in error path" → NOT your scope (control flow = Agent B)

### Input Validation

- User input passed to SQL / HTML / commands without sanitization
- Insufficient path parameter validation (directory traversal)
- Upload file type/size validation
- Deserialization safety (JSON / YAML / pickle, etc.)

> **Caller tracing obligation for injection/dispatch findings:**
> When you find dynamic SQL, `eval`, `const_get`, dynamic dispatch, or similar patterns:
>
> 1. Grep for all call sites of the function/method
> 2. For each caller, determine if the dangerous parameter originates from user input, external data, or hardcoded values
> 3. If ALL callers pass hardcoded/internal values: report as **Low** (defense-in-depth), not Critical/High
> 4. If ANY caller passes user-controlled input: report at full severity with the specific call chain

### Authorization & Authentication

- Missing authorization checks on API endpoints
- Missing tenant isolation in multi-tenant environments
- Possible access to other users' resources (IDOR)
- Token/session expiration checks

### External Service Integration

- Missing timeout settings on API calls
- Idempotency not considered during retries
- Vulnerability to response format changes (field additions/removals)
- Hardcoded secrets/credentials
