# Bug Hunt Report Template

## Severity Criteria

| Severity | Criteria | Examples |
|----------|----------|----------|
| Critical | Potential data corruption, security breach, or process crash | SQL injection, missing authorization, panic/abort |
| High | Potential production errors affecting users | nil reference, unhandled exceptions, silent data loss |
| Medium | Issues that manifest only under specific conditions | Boundary values, race conditions, edge-case failures |
| Low | Defensive coding gaps with unlikely but possible production impact | Insufficient error context, missing validation on internal data |

Note: Code style issues, development-only behavior, and improvement suggestions are NOT reported.
These belong in code reviews, not bug hunts.

## Output Format

````markdown
## Bug Hunt Report

**Target:** [file path / directory / feature name]
**Date:** [today's date]
**Files examined:** N

---

### Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | N |
| 🟠 High | N |
| 🟡 Medium | N |
| 🔵 Low | N |

---

### 🔴 Critical

#### 1. [Bug summary]

- **File:** `path/to/file.rb:42`
- **Category:** [Data Safety / Control Flow / Security]
- **Issue:** [What is the problem]
- **Reproduction:** [Under what conditions does it manifest]
- **Impact:** [What happens]
- **Suggested fix:**
```diff
- problematic code
+ fixed code
```

---

### 🟠 High

(same format)

---

### 🟡 Medium

(same format)

---

### 🔵 Low

| # | File | Category | Summary |
|---|------|----------|---------|
| 1 | `path:line` | Data Safety | ... |
| 2 | `path:line` | Control Flow | ... |

---

### Cross-Implementation Comparison (when parallel implementations are investigated)

If the investigation targets include parallel implementations (e.g., platform-specific workers,
similar modules for different services), add a comparison matrix showing behavioral differences:

| Feature | impl_A | impl_B | impl_C | impl_D |
|---------|:------:|:------:|:------:|:------:|
| [Key behavior 1] | ✅ | ❌ | ❌ | ✅ |
| [Key behavior 2] | ✅ | ✅ | ❌ | N/A |

Use ✅ (correct/present), ❌ (missing/incorrect), N/A (not applicable).
Identify the most robust implementation as the reference pattern.

---

### Investigation Coverage

| Perspective | Investigated | Notes |
|-------------|-------------|-------|
| Null / Undefined | ✅ | |
| Type Safety | ✅ | |
| Boundary Values | ✅ | |
| Branch Coverage | ✅ | |
| Error Handling | ✅ | |
| Concurrency | ✅ / ⬜ N/A | |
| Input Validation | ✅ | |
| Authorization | ✅ / ⬜ N/A | |
| External Integration | ✅ / ⬜ N/A | |

### Cross-Reference

| Report | Date | Deduplicated |
|--------|------|--------------|
| `bug-hunt-YYYY-MM-DD-HHmm.md` | YYYY-MM-DD | N findings excluded |

(Omit this section if no prior reports exist)

### Next Steps

- Early fixes recommended for Critical / High items
````

## When No Bugs Are Found

If no bugs are found after investigation, output a brief summary instead of the full report:

````markdown
## Bug Hunt Report

**Target:** [file path / directory / feature name]
**Date:** [today's date]
**Files examined:** N

### Result: No issues found ✅

[Brief summary of what was investigated and why no issues were identified.]

### Investigation Coverage

(same coverage table as above)
````
