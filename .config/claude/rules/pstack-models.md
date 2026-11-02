# pstack model configuration

One line per role. Delete a line to fall back to the skill default.
`inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Task `model`). Alias entries in a panel list still count toward its fan-out.

`codex` as a value: run that seat on Codex instead of the `Agent` tool, and only for a read-only seat. Make a fresh output dir per run with `mktemp -d`, write the seat's filled prompt to `<out>/prompt.md`, and in the same message as the other seats start `codex exec -s read-only -C <repo root> -o <out>/result.md - < <out>/prompt.md` with Bash `run_in_background: true`. Merge `<out>/result.md` like any other seat's report, crediting it to `codex`, only after the completion notice arrives with exit code 0 and that file exists. Otherwise report the seat as vacant with the exit code and the gist of stderr: never merge it as "no findings" and never rerun it on Claude.

This file is managed declaratively in the dotfiles repo at `.config/claude/rules/pstack-models.md`. In `setup-pstack`, skip detecting models, choosing a budget, and writing the rule; tell the user to edit that repo file instead.

budget: small (medium)

feature, refactoring: inherit-parent
bug-fix: inherit-parent
perf-issue: inherit-parent
hillclimb: inherit-parent
judgment and prose: opus medium
hardest tasks: opus medium
how explorer: inherit-parent
how explainer: opus medium
why investigators: inherit-parent
why synthesizer: opus medium
reflect tooling: inherit-parent
reflect judgment, divergent, synthesizer: opus medium
arena runners: opus medium, inherit-parent
arena cross-judge pool: opus medium, inherit-parent
swarm workers: inherit-parent
architect runners: opus medium, inherit-parent
interrogate reviewers: opus medium, codex
