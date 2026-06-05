#!/usr/bin/env bash
# PreToolUse guard for `gh api`.
#
# Gated in settings.json by `if: "Bash(gh api *)"`, which fires on a per-subcommand
# prefix match (or when a command is too complex to parse). So this script only
# runs once a `gh api` invocation is already known to be present (or unparsable).
# It then auto-allows only when it can affirmatively prove the call is read-only;
# any uncertainty falls through to "ask" (fail-safe).
#
# The check is presence-based, so it is robust to chained/sequenced calls
# (`gh api … && gh api … -X DELETE`) by construction: a write indicator anywhere
# in the command forces "ask", and no per-call state can let an early read mask a
# later write. We auto-allow ONLY when ALL of these hold:
#   - every HTTP method override present is GET/HEAD (each token is inspected,
#     since pflag honours the last one and a command may carry several); AND
#   - no body-bearing flag (--field/-F, --raw-field/-f, --input) is present, since
#     any of them defaults gh to POST; AND
#   - no indirect invocation (eval / sh -c / xargs / subshell) hides the verb.
# Any override that is not provably GET/HEAD — POST/PUT/PATCH/DELETE, an unknown
# verb, or a non-literal value like `-X "$M"` whose verb we cannot read — and any
# body flag fall to "ask".
#
# Detection accounts for gh/pflag shorthand quirks so the canonical *and* the
# obfuscated forms are covered:
#   - combined shorthand   -iX DELETE      (X is the value-taking flag at the tail)
#   - attached value       -XDELETE, -Fname=v, -F'name=v', -F1=2
#   - = / whitespace (incl. tab) separators:  --method=POST, -X<tab>DELETE
#   - repeated overrides   -X GET -X DELETE  (every one is inspected, not just the first)
#   - dynamic long flags    --method$M, --field"$F", --input\=file (ask)
# Note the deliberate trade-off: because we cannot tokenize the raw string, a
# read whose value text merely *contains* a write-looking substring (e.g.
# `--jq '… -X DELETE …'`) is over-asked. Over-asking a read is fail-safe; the
# inverse (a value's text suppressing a real write check) is the bug class this
# presence-based design avoids.
#
# Note: `eval "gh api …"` (gh api buried inside eval's string arg) never trips
# the `if` gate, so this script won't see it — that form is blocked upstream by
# the banned-commands `eval` rule instead.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Defensive re-check that a `gh api` token is actually present. The `if` gate
# already guarantees this for parseable commands; this also covers the
# "too complex to parse" fallback, where the gate fires without a confirmed match.
# POSIX classes only (no \s / \b) so BSD/macOS grep matches identically; an
# over-broad match here is harmless (the analysis below still gates the decision),
# whereas an under-match would skip the guard entirely.
if ! echo "$CMD" | grep -qE 'gh[[:space:]]+api'; then
  exit 0
fi

ask() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

allow() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# --- Dynamic/escaped long flags --------------------------------------------
# Shell expansion and escaping can build a guarded long flag after this raw-text
# check runs: `--method$M` may execute as `--method=DELETE`, and `--field"$F"` as
# `--field=title`. Since we cannot prove the final argv here, ask. Literal
# separators (`--method=GET`, `--method GET`) are handled by the specific checks
# below so explicit read-only methods can still be auto-allowed.
for guarded_flag in --method --field --raw-field --input; do
  if echo "$CMD" | grep -qF -- "${guarded_flag}"'$' ||
    echo "$CMD" | grep -qF -- "${guarded_flag}\"" ||
    echo "$CMD" | grep -qF -- "${guarded_flag}'" ||
    echo "$CMD" | grep -qF -- "${guarded_flag}\\"; then
    ask "gh api: non-literal ${guarded_flag} flag — confirm intent"
  fi
done

# --- HTTP method override --------------------------------------------------
# gh's flags are case-sensitive (`-X`, `--method`); the verb is matched
# case-insensitively (POSIX bracket classes, not bash 4's ${v,,}) since
# `--method get` is accepted. EVERY override token is inspected — read-only holds
# only if every verb is GET/HEAD. A non-literal value (`-X "$M"`) extracts to an
# empty verb and is therefore treated as not-GET/HEAD.
#
# override_token_re grabs a `-…X` / combined `-iX` / `--method` flag together
# with its value, whether glued (`-XDELETE`) or separated by space/=/tab.
override_token_re='(-[[:alnum:]]*X[[:space:]=]*[A-Za-z]*|--method[[:space:]=]+[A-Za-z]*)'
while IFS= read -r tok; do
  [ -z "$tok" ] && continue
  # Strip the flag (`-…X` / `--method`) and separators; what remains is the verb.
  # Anchored so a glued value (`-XGET`) does not fold the flag's `X` into the verb.
  verb=""
  if [[ "$tok" =~ ^-[[:alnum:]]*X[[:space:]=]*([A-Za-z]*)$ ]]; then
    verb="${BASH_REMATCH[1]}"
  elif [[ "$tok" =~ ^--method[[:space:]=]+([A-Za-z]*)$ ]]; then
    verb="${BASH_REMATCH[1]}"
  fi
  case "$verb" in
  [Gg][Ee][Tt] | [Hh][Ee][Aa][Dd]) ;; # read-only verb
  *) ask "gh api: HTTP method override to '${verb:-?}' (not GET/HEAD) — confirm intent" ;;
  esac
done < <(echo "$CMD" | grep -oE -- "$override_token_re" || true)

# --- Body-bearing flags ----------------------------------------------------
# --field/-F, --raw-field/-f, --input all default the request to POST. The
# shorthand clause matches a flag-position `-…[Ff]` bundle (covers `-f`, `-F`,
# combined `-iF`, and attached `-Fname=v` / `-F'name=v'` / `-F1=2`) regardless of
# the following character — earlier the clause required a letter/space/= next, so
# values glued via a quote, digit or bracket slipped through and a POST was
# auto-allowed. Body presence alone forces "ask" (no GET/HEAD exception): the
# lone read that carried a body, `-X GET … -f q=` search, is now over-asked, which
# is the fail-safe price of not letting body detection be suppressible.
body_re='(--field([[:space:]=]|$)|--raw-field([[:space:]=]|$)|--input([[:space:]=]|$)|(^|[[:space:]])-[[:alnum:]]*[Ff])'
if echo "$CMD" | grep -qE -- "$body_re"; then
  ask "gh api: body-bearing flag (-f/-F/--field/--raw-field/--input) implies POST"
fi

# --- Indirect invocation ---------------------------------------------------
# Hides the real command from the regex layers above. Case-insensitive to also
# catch EVAL/BASH-style shouted variants.
shell_wrap_re='(\beval\b|\b(bash|sh)[[:space:]]+-c\b|\bxargs\b|`|\$\()'
if echo "$CMD" | grep -qiE -- "$shell_wrap_re"; then
  ask "gh api: indirect invocation (eval / sh -c / xargs / subshell) — confirm intent"
fi

# Proven read-only: no method override (or GET/HEAD), no body flag, no indirection.
allow "gh api: read-only (GET/HEAD)"
