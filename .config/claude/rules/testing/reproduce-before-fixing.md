---
paths:
  - "**/*.rs"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.go"
  - "**/*.lua"
  - "**/*.zig"
---

# Reproduce Before Fixing

Before changing code to fix a bug, write a test that reproduces it and fails.
Make that test pass, and keep it. A fix without a reproducing test is unverified.

If a reproducing test is impractical, say so and state how the fix was verified
manually.
