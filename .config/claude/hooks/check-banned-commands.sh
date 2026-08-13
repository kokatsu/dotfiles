#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(dirname "${BASH_SOURCE[0]}")"
RULES_FILE="$HOOKS_DIR/banned-commands.json"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Claude and Codex share this best-effort Herdr command guard. It prevents
# ordinary bypasses but is not a security boundary for arbitrary Bash access.
printf '%s' "$INPUT" | bash "$HOOKS_DIR/herdr-peer-command-guard.sh"

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

# Git-specific guards (external-diff and shallow-fetch). Both are per-command
# rules, kept out of banned-commands.json: each executed command is taken from
# the bash AST (shfmt --tojson) and analyzed argument-wise in jq, keeping
# CallExpr.Args as a JSON array so argument boundaries survive. Words are
# resolved (quotes, backslashes, ANSI-C \x/\u/\U/octal escapes), wrappers
# (command/env with their options) are stripped, git global options are skipped
# to find the subcommand, and flags are compared as whole arguments — quoting
# can neither hide a flag ("--depth") nor fake one ('--depth 1' as a single
# argument). Comments and heredoc bodies are plain text in the AST and never
# analyzed; command substitutions (even inside double quotes or unquoted
# heredocs) contain real CallExpr nodes and are visited by the recursive walk.
# If the command cannot be parsed (bash syntax error, shfmt/jq missing), fail
# closed with exit 2: an unparsed command must not run unchecked.
# shellcheck disable=SC2016  # $flags etc. are jq variables, not shell expansions
analyze_git='
  def hexval:
    {"0":0,"1":1,"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,
      "a":10,"b":11,"c":12,"d":13,"e":14,"f":15}[.];
  def ansi_decode:
    ([scan("\\\\x[0-9a-fA-F]{1,2}|\\\\u[0-9a-fA-F]{1,4}|\\\\U[0-9a-fA-F]{1,8}|\\\\[0-7]{1,3}|\\\\.|[^\\\\]+")
      | if test("^\\\\[xuU]") then
          [.[2:] | ascii_downcase | split("")[] | hexval] | [reduce .[] as $d (0; . * 16 + $d)] | implode
        elif test("^\\\\[0-7]") then
          [.[1:] | split("")[] | tonumber] | [reduce .[] as $d (0; . * 8 + $d)] | implode
        elif startswith("\\\\") then
          {"n":"\n","t":"\t","r":"\r","a":"\u0007","b":"\b","e":"\u001b","f":"\f","v":"\u000b"}[.[1:]] // .[1:]
        else . end
    ] | join(""));
  def word_text:
    [.Parts[]?
      | if .Type == "Lit" then ((.Value // "") | gsub("\\\\"; ""))
        elif .Type == "SglQuoted" then
          (if .Dollar then ((.Value // "") | (try ansi_decode catch .)) else (.Value // "") end)
        elif .Type == "DblQuoted" then ([.Parts[]? | if .Type == "Lit" then (.Value // "") else "" end] | join(""))
        else "" end
    ] | join("");
  # env -S の値の分割を模す: 空白と引用符外の \_ が引数区切り、"..." /
  # \u0027...\u0027 の引用とバックスラッシュエスケープを解決し、ダブル
  # クォート内の \_ は引数内の空白になる (\u0027 はシェルの単一引用符内
  # に置けないアポストロフィ)。区切りもトークンとして消費してから
  # 捨てることで、\_ の _ が次の語に接着するのを防ぐ。
  # 展開結果は env オプションとして再解析する。
  def s_split:
    [scan("\\\\_|[[:space:]]+|(?:[^[:space:]\"\u0027\\\\]|\\\\[^_]|\"(?:[^\"\\\\]|\\\\.)*\"|\u0027[^\u0027]*\u0027)+")]
    | map(select(test("^(\\\\_|[[:space:]]+)$") | not))
    | map(
        gsub("\"(?<q>(?:[^\"\\\\]|\\\\.)*)\""; "\(.q | gsub("\\\\_"; " "))")
        | gsub("\u0027(?<q>[^\u0027]*)\u0027"; "\(.q)")
        | gsub("\\\\(?<c>.)"; "\(.c)")
      );
  def strip_command_opts:
    if length > 0 and (.[0] == "-p" or .[0] == "--") then (.[1:] | strip_command_opts) else . end;
  def strip_env_opts:
    if length == 0 then .
    elif .[0] == "-u" or .[0] == "-C" or .[0] == "--unset" or .[0] == "--chdir" then (.[2:] | strip_env_opts)
    elif .[0] == "-S" then (((.[1] // "" | s_split) + .[2:]) | strip_env_opts)
    elif .[0] == "--split-string" then (((.[1] // "" | s_split) + .[2:]) | strip_env_opts)
    elif (.[0] | startswith("--split-string=")) then (((.[0] | .[15:] | s_split) + .[1:]) | strip_env_opts)
    elif (.[0] | test("^-[i0v]*S")) then
      .[0] as $opt
      | ($opt | capture("^-[i0v]*S(?<value>.*)$").value) as $value
      | if $value == ""
        then (((.[1] // "" | s_split) + .[2:]) | strip_env_opts)
        else ((($value | s_split) + .[1:]) | strip_env_opts)
        end
    elif (.[0] | test("^-|^[A-Za-z_][A-Za-z0-9_]*=")) then (.[1:] | strip_env_opts)
    else . end;
  def strip_wrappers:
    if length == 0 then .
    elif .[0] == "command" then (.[1:] | strip_command_opts | strip_wrappers)
    elif .[0] == "env" then (.[1:] | strip_env_opts | strip_wrappers)
    else . end;
  def skip_git_globals:
    if length == 0 then .
    elif .[0] == "-C" or .[0] == "-c" or .[0] == "--git-dir" or .[0] == "--work-tree"
      or .[0] == "--namespace" or .[0] == "--config-env" then (.[2:] | skip_git_globals)
    elif (.[0] | startswith("-")) then (.[1:] | skip_git_globals)
    else . end;
  def has_flag($flags):
    any(.[]; . as $a | any($flags[]; . as $f | $a == $f or ($a | startswith($f + "="))));
  [.. | objects | select(.Type? == "CallExpr") | [.Args[]? | word_text]]
  | .[]
  | strip_wrappers
  | select(length > 0 and .[0] == "git")
  | (.[1:] | skip_git_globals) as $r
  | select(($r | length) > 0)
  | $r[0] as $sub
  | ($r[1:]) as $args
  | if ($sub == "fetch" or $sub == "pull")
      and ($args | has_flag(["--depth", "--shallow-since", "--shallow-exclude", "--update-shallow"]))
    then "SHALLOW"
    elif ($sub == "diff" or $sub == "show"
        or ($sub == "log" and ($args | any(.[]; . == "-p" or . == "-u" or . == "--patch"))))
      and (($args | any(.[]; . == "--no-ext-diff")) | not)
    then "EXTDIFF"
    else empty end
'
if ! verdicts=$(printf '%s\n' "$CMD" | shfmt --tojson 2>/dev/null | jq -r "$analyze_git" 2>/dev/null); then
  echo "banned-commands hook could not parse this command as bash (syntax error, or shfmt/jq unavailable); refusing to run it unchecked. Fix the command and retry." >&2
  exit 2
fi

if [[ $verdicts == *SHALLOW* ]]; then
  echo "Refuse shallow git fetch/pull (--depth/--shallow-*) because it makes the existing repository shallow. Use a temporary shallow clone (git clone --depth), or fetch normally. --deepen/--unshallow remain allowed." >&2
  exit 2
fi

if [[ $verdicts == *EXTDIFF* ]]; then
  echo "Add --no-ext-diff to git diff/show/log -p. The global git config sets diff.external=difft, which mangles diff output when captured as tool output; --no-ext-diff is the only reliable bypass (an empty diff.external= override errors out)." >&2
  exit 2
fi
