---
name: {{SKILL_NAME}}
description: This skill should be used when the user asks to "{{TRIGGER_EN_1}}", "{{TRIGGER_EN_2}}", "{{TRIGGER_JA_1}}", "{{TRIGGER_JA_2}}".
argument-hint: "{{ARGUMENT_HINT}}"
version: 1.0.0
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Task
  - WebFetch
  - WebSearch
disable-model-invocation: false
---

# {{SKILL_NAME}}

{{DESCRIPTION}}

## Usage

```
/{{SKILL_SLUG}} {{ARGUMENT_HINT}}
```

## Context

Current working directory:
!`pwd`

Git branch:
!`git branch --show-current 2>/dev/null || echo "not a git repo"`

## Prerequisites

- {{PREREQUISITE_1}}
- {{PREREQUISITE_2}}

## Workflow

### Step 1: {{STEP_1_TITLE}}

{{STEP_1_INSTRUCTIONS}}

### Step 2: {{STEP_2_TITLE}}

{{STEP_2_INSTRUCTIONS}}

### Step 3: {{STEP_3_TITLE}}

{{STEP_3_INSTRUCTIONS}}

## Error Handling

| Error | Solution |
|-------|----------|
| {{ERROR_1}} | {{SOLUTION_1}} |
| {{ERROR_2}} | {{SOLUTION_2}} |

## Examples

### Example 1: {{EXAMPLE_1_TITLE}}

```
/{{SKILL_SLUG}} {{EXAMPLE_1_ARGS}}
```

{{EXAMPLE_1_DESCRIPTION}}

### Example 2: {{EXAMPLE_2_TITLE}}

```
/{{SKILL_SLUG}} {{EXAMPLE_2_ARGS}}
```

{{EXAMPLE_2_DESCRIPTION}}
