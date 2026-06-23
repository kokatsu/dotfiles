#!/usr/bin/env bash
set -euo pipefail

RULES_FILE="$(dirname "${BASH_SOURCE[0]}")/banned-commands.json"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Parse the full ruleset in two jq passes so the per-rule match loop can run
# entirely in-shell. With ~13 rules this avoids ~26 jq subprocess forks per
# Bash tool call (this hook runs on every Claude Bash invocation).
# while-read instead of mapfile to stay compatible with stock macOS Bash 3.2.
patterns=()
messages=()
while IFS= read -r line; do patterns+=("$line"); done < <(jq -r '.[].pattern' "$RULES_FILE")
while IFS= read -r line; do messages+=("$line"); done < <(jq -r '.[].message' "$RULES_FILE")

for i in "${!patterns[@]}"; do
  if [[ $CMD =~ ${patterns[i]} ]]; then
    printf '%s\n' "${messages[i]}" >&2
    exit 2
  fi
done

# External-diff guard for git. Kept out of banned-commands.json because the
# rule is per-sub-command: split the compound command on shell separators so a
# guarded segment (... --no-ext-diff) cannot vouch for an unguarded sibling.
# Between `git` and the subcommand only dash-prefixed global options (and their
# values, e.g. -C <path>, -c <k=v>, --no-pager) are skipped, so an argument that
# merely contains "diff" (git commit -m "...diff...") is not matched. difftastic's
# diff.external mangles captured output unless --no-ext-diff is passed (see
# CLAUDE.md Git Diffs).
git_diff_show='^[[:space:]]*git[[:space:]]+(-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?[[:space:]]+)*(diff|show)([[:space:]]|$)'
git_log_patch='^[[:space:]]*git[[:space:]]+(-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?[[:space:]]+)*log[[:space:]]+([^[:space:]]+[[:space:]]+)*(-p|-u|--patch)([[:space:]]|$)'
while IFS= read -r seg; do
  [[ $seg == *--no-ext-diff* ]] && continue
  if [[ $seg =~ $git_diff_show || $seg =~ $git_log_patch ]]; then
    echo "Add --no-ext-diff to git diff/show/log -p (difft external diff mangles captured output). See CLAUDE.md Git Diffs." >&2
    exit 2
  fi
done < <(printf '%s\n' "$CMD" | tr ';&|()' '\n')
