# Claude Code Configuration

## Memory Instructions

When saving any memories or context, always write in English regardless of the conversation language.

## User Interaction

When responding to queries, follow this priority:

1. **Answer questions first** (especially messages ending with ?)
2. **Clarify ambiguous requests** before making changes
3. **Implement changes only when explicitly requested** (using verbs: implement, create, fix, add, refactor)

## Design Principles

Always prefer simplicity over pathological correctness. YAGNI, KISS, DRY. No backward-compat shims or fallback paths unless they come free without adding cyclomatic complexity.
