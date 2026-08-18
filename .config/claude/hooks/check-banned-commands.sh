#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(dirname "${BASH_SOURCE[0]}")"
RULES_FILE="$HOOKS_DIR/banned-commands.json"
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Claude and Codex share this best-effort Herdr command guard. It prevents
# ordinary bypasses but is not a security boundary for arbitrary Bash access.
printf '%s' "$INPUT" | bash "$HOOKS_DIR/herdr-peer-command-guard.sh"

# banned-commands.json holds only textual patterns (pipe-to-shell, redirect
# targets, env-assignment prefixes) that have no single CallExpr to anchor on;
# command-name rules live in the AST analysis below, which regex separator
# lists cannot cover (newlines, then/do, wrappers, backticks all bypass them).
# Parse the ruleset in two jq passes so the per-rule match loop can run
# entirely in-shell, avoiding two jq subprocess forks per rule per Bash call.
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

# Command-name guards (rm/eval/dd/mkfs/chmod/shred/grep -r and the git rules):
# each executed command is taken from the bash AST (shfmt --tojson) and
# analyzed argument-wise in jq, keeping CallExpr.Args as a JSON array so
# argument boundaries survive. Words are resolved (quotes, backslashes, ANSI-C
# \x/\u/\U/octal escapes), wrappers (command/env/sudo/doas with their options)
# are stripped, git global options are skipped to find the subcommand, and
# flags are compared as whole arguments — quoting can neither hide a flag
# ("--depth") nor fake one ('--depth 1' as a single argument). Matching the
# first word of every CallExpr covers positions a separator regex cannot:
# newline-separated commands, then/do bodies, backticks, and wrapper prefixes.
# Comments and heredoc bodies are plain text in the AST and never analyzed;
# command substitutions (even inside double quotes or unquoted heredocs)
# contain real CallExpr nodes and are visited by the recursive walk.
# If the command cannot be parsed (bash syntax error, shfmt/jq missing), fail
# closed with exit 2: an unparsed command must not run unchecked.
# shellcheck disable=SC2016  # $flags etc. are jq variables, not shell expansions
analyze='
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
  # Short options may be clustered ("sudo -nu root"): scan the cluster left to
  # right; an argument-taking letter at the end consumes the next word, one in
  # the middle takes the rest of the token as its attached value.
  def cluster_eats($argchars):
    if length == 0 then false
    else .[0:1] as $c
    | if ($argchars | contains($c)) then (length == 1)
      else (.[1:] | cluster_eats($argchars)) end
    end;
  # Clusters containing -v/-V make command non-executing, so only pure -p
  # clusters are stripped. After "--" the next word is the command name even
  # when it looks like an option, so option stripping stops there.
  def strip_command_opts:
    if length == 0 then .
    elif .[0] == "--" then .[1:]
    elif (.[0] | test("^-p+$")) then (.[1:] | strip_command_opts)
    else . end;
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
    elif (.[0] | test("^-[A-Za-z0]+$")) then
      (if (.[0] | .[1:] | cluster_eats("uC")) then (.[2:] | strip_env_opts)
        else (.[1:] | strip_env_opts) end)
    elif (.[0] | test("^-|^[A-Za-z_][A-Za-z0-9_]*=")) then (.[1:] | strip_env_opts)
    else . end;
  def strip_sudo_opts:
    if length == 0 then .
    elif .[0] == "--" then .[1:]
    elif .[0] == "--chdir" or .[0] == "--chroot" or .[0] == "--close-from"
      or .[0] == "--command-timeout" or .[0] == "--group" or .[0] == "--host"
      or .[0] == "--other-user" or .[0] == "--prompt" or .[0] == "--role"
      or .[0] == "--type" or .[0] == "--user" then (.[2:] | strip_sudo_opts)
    elif (.[0] | test("^-[A-Za-z]+$")) then
      (if (.[0] | .[1:] | cluster_eats("aCDghprRtTuU")) then (.[2:] | strip_sudo_opts)
        else (.[1:] | strip_sudo_opts) end)
    elif (.[0] | test("^-|^[A-Za-z_][A-Za-z0-9_]*=")) then (.[1:] | strip_sudo_opts)
    else . end;
  def strip_exec_opts:
    if length == 0 then .
    elif .[0] == "--" then .[1:]
    elif (.[0] | test("^-[A-Za-z]+$")) then
      (if (.[0] | .[1:] | cluster_eats("a")) then (.[2:] | strip_exec_opts)
        else (.[1:] | strip_exec_opts) end)
    elif (.[0] | test("^-")) then (.[1:] | strip_exec_opts)
    else . end;
  def strip_wrappers:
    if length == 0 then .
    elif .[0] == "command" then (.[1:] | strip_command_opts | strip_wrappers)
    elif .[0] == "env" then (.[1:] | strip_env_opts | strip_wrappers)
    elif .[0] == "sudo" or .[0] == "doas" then (.[1:] | strip_sudo_opts | strip_wrappers)
    elif .[0] == "exec" then (.[1:] | strip_exec_opts | strip_wrappers)
    elif .[0] == "builtin" then
      (.[1:] | (if length > 0 and .[0] == "--" then .[1:] else . end) | strip_wrappers)
    else . end;
  def skip_git_globals:
    if length == 0 then .
    elif .[0] == "-C" or .[0] == "-c" or .[0] == "--git-dir" or .[0] == "--work-tree"
      or .[0] == "--namespace" or .[0] == "--config-env" then (.[2:] | skip_git_globals)
    elif (.[0] | startswith("-")) then (.[1:] | skip_git_globals)
    else . end;
  def has_flag($flags):
    any(.[]; . as $a | any($flags[]; . as $f | $a == $f or ($a | startswith($f + "="))));
  # Walk a git subcommand argument list up to the pathspec terminator, first
  # consuming the separate value of any option in $valopts — that value may
  # itself be the string "--", which must not read as the terminator ("git
  # clean -e -- -fd"). Values are dropped so they never scan as flags.
  # Flag letters of a short cluster stop at the first argument-taking letter:
  # in "git clean -fed" the "d" is the attached value of -e, not a flag. A
  # non-alphanumeric character also ends the scan, so an attached value with
  # punctuation ("-fofoo-bar") cannot hide the flags before it.
  def cluster_flags($argchars):
    if length == 0 then ""
    else .[0:1] as $c
    | if ($argchars | contains($c)) or (($c | test("[A-Za-z0-9]")) | not) then ""
      else ($c + (.[1:] | cluster_flags($argchars))) end
    end;
  def git_opts($valopts; $argchars):
    if length == 0 then []
    elif (.[0] as $t | $valopts | index($t)) then ([.[0]] + (.[2:] | git_opts($valopts; $argchars)))
    elif (.[0] | test("^-[A-Za-z0-9]")) and (.[0] | .[1:] | cluster_eats($argchars))
    then ([.[0]] + (.[2:] | git_opts($valopts; $argchars)))
    elif .[0] == "--" then []
    else [.[0]] + (.[1:] | git_opts($valopts; $argchars)) end;
  # Option scanning stops at "--"; everything after it is an operand, so a file
  # literally named "-R" cannot look like a flag.
  def opts_before_ddash:
    if length == 0 then [] elif .[0] == "--" then [] else [.[0]] + (.[1:] | opts_before_ddash) end;
  # GNU getopt_long / git parse-options accept any unambiguous long-option
  # prefix ("--rec" is --recursive), so flag checks match prefixes down to the
  # shortest unambiguous length. An attached =value is cut before comparing.
  def is_abbrev_of($full; $minlen):
    sub("=.*$"; "") as $t
    | ($t | length) >= $minlen and ($full | startswith($t));
  # grep option walk: "--" ends option parsing, and the operand of -e/-f
  # (pattern / pattern-file) or -d/-D (action) is data whether separate
  # ("-e -r"), attached ("-eerror", "-dread"), or clustered ("-ner file"),
  # so only an r/R that appears before any of those letters in a cluster
  # means recursion. Digits stay in the scan: "-n2r" is a valid recursive
  # cluster (context count), so the cluster shape allows them.
  def grep_cluster_verdict:
    if length == 0 then "plain"
    elif (.[0:1] | test("[rR]")) then "recursive"
    elif (.[0:1] | test("[efdD]")) then (if length == 1 then "eats_next" else "plain" end)
    else (.[1:] | grep_cluster_verdict) end;
  def grep_recursive:
    if length == 0 then false
    elif .[0] == "--" then false
    elif (.[0] | is_abbrev_of("--recursive"; 5) or is_abbrev_of("--dereference-recursive"; 5))
    then true
    elif (.[0]
      | (contains("=") | not)
        and (is_abbrev_of("--regexp"; 5) or . == "--file"
          or is_abbrev_of("--devices"; 5) or is_abbrev_of("--directories"; 5)))
    then (.[2:] | grep_recursive)
    elif (.[0] | test("^-[A-Za-z0-9]+$")) then
      ((.[0] | .[1:] | grep_cluster_verdict) as $v
        | if $v == "recursive" then true
          elif $v == "eats_next" then (.[2:] | grep_recursive)
          else (.[1:] | grep_recursive) end)
    else (.[1:] | grep_recursive) end;
  # Git identity comes from the includeIf entries in ~/.config/git/config.local,
  # and user.useConfigOnly makes git fail loudly where none matches, so nothing
  # should set it per repository. Section and key are case-insensitive.
  def is_identity_key:
    ascii_downcase | . == "user.email" or . == "user.name";
  def identity_assignment:
    ascii_downcase | startswith("user.email=") or startswith("user.name=");
  # git config options that take a SEPARATE value; their value is data and must
  # not be mistaken for the key or for the value that makes an invocation a write.
  def config_operands:
    if length == 0 then []
    elif (.[0] as $t | ["-f", "--file", "--blob", "-t", "--type", "--default",
      "--comment", "--value"] | index($t)) then (.[2:] | config_operands)
    elif (.[0] | startswith("-")) then (.[1:] | config_operands)
    else [.[0]] + (.[1:] | config_operands) end;
  # A write is an identity key with a value after it ("git config user.email x",
  # "git config set user.email x"), or one named by a removing/adding option.
  # A key with nothing after it is a read ("git config --get user.email").
  def config_identity_write:
    . as $rest
    | ($rest | config_operands) as $ops
    | ([$ops | to_entries[] | select(.value | is_identity_key) | .key] | first) as $i
    | if $i == null then false
      else ($ops[0] // "" | ascii_downcase) as $head
      | ($head == "set" or $head == "add" or $head == "unset"
          or $head == "unset-all" or $head == "replace-all")
        or ($rest | any(.[]; . == "--unset" or . == "--unset-all"
          or . == "--replace-all" or . == "--add"))
        or (($ops | length) > $i + 1)
      end;
  # git -c user.email=... and --config-env=user.email=VAR set an identity for one
  # invocation. Checked before skip_git_globals drops the option and its value.
  def git_global_identity:
    if length == 0 then false
    elif .[0] == "-c" or .[0] == "--config-env" then
      (((.[1] // "") | identity_assignment) or (.[2:] | git_global_identity))
    elif (.[0] | ascii_downcase | startswith("-cuser.email=")
      or startswith("-cuser.name=")) then true
    elif (.[0] | startswith("--config-env=")) then
      (((.[0] | .[13:]) | identity_assignment) or (.[1:] | git_global_identity))
    elif (.[0] | startswith("-")) then (.[1:] | git_global_identity)
    else false end;
  def git_verdict:
    if git_global_identity then "GIT_IDENTITY"
    else (. | skip_git_globals) as $r
    | if ($r | length) == 0 then empty
      else $r[0] as $sub
      # After "--" every token is a pathspec/refspec, so flag scans only look
      # before the terminator — both to keep a path named "--force" from
      # reading as a flag and to keep a path named "--no-ext-diff" from
      # defusing the external-diff guard.
      | (if $sub == "clean" then {opts: ["-e", "--exclude"], chars: "e"}
          elif $sub == "fetch" or $sub == "pull" then
            {opts: ["--upload-pack", "-o", "--server-option", "--negotiation-tip", "--refmap",
              "-j", "--jobs", "--depth", "--shallow-since", "--shallow-exclude"], chars: "jo"}
          elif $sub == "push" then
            {opts: ["--receive-pack", "--exec", "--repo", "-o", "--push-option"], chars: "o"}
          # Verified against the installed git: these accept a SEPARATE value
          # (bare form errors, "opt value" runs). Options that are bare-valid
          # (-U, --unified, --pretty, --format) or equals-only (--date,
          # --max-count, --skip, -l) must NOT be listed — treating them as
          # consuming would eat a real "--" terminator.
          elif $sub == "diff" or $sub == "show" or $sub == "log" then
            {opts: ["-G", "-S", "-O", "-n", "-L", "--since", "--until", "--author",
              "--committer", "--grep", "--output", "--rotate-to", "--skip-to",
              "--find-object", "--decorate-refs", "--decorate-refs-exclude"],
              chars: "GSOnL"}
          else {opts: [], chars: ""} end) as $vo
      | ($r[1:] | git_opts($vo.opts; $vo.chars)) as $args
      | if $sub == "push"
          and ($args | any(.[]; . == "--force"
            or (test("^-[A-Za-z0-9]") and (.[1:] | cluster_flags("o") | contains("f")))))
        then "FORCE_PUSH"
        elif $sub == "clean"
          and ((([$args[] | select(test("^-[A-Za-z0-9]")) | .[1:] | cluster_flags("e")] | add // "")
              + (if ($args | any(.[]; is_abbrev_of("--force"; 3))) then "f" else "" end)) as $f
            | ($f | contains("f")) and (($f | contains("d")) or ($f | contains("x"))))
        then "GIT_CLEAN"
        elif $sub == "reset" and ($args | any(.[]; . == "--hard"))
          and ($args | any(.[]; startswith("origin/") or startswith("upstream/")
              or startswith("HEAD~") or startswith("HEAD@")))
        then "GIT_RESET_HARD"
        elif ($sub == "fetch" or $sub == "pull")
          and ($args | has_flag(["--depth", "--shallow-since", "--shallow-exclude", "--update-shallow"]))
        then "SHALLOW"
        elif $sub == "config" and ($r[1:] | config_identity_write)
        then "GIT_IDENTITY"
        # --author only rewrites authorship on the commands that record it;
        # "git log --author" is a filter and stays allowed.
        elif ($sub == "commit" or $sub == "am")
          and ($args | any(.[]; is_abbrev_of("--author"; 4)))
        then "GIT_IDENTITY"
        # These run a command given as a single string, which shfmt parses as one
        # word, so the identity check below never sees it. Match the fragment in
        # the string instead - nothing legitimate passes an identity key here.
        elif ($sub == "rebase" or $sub == "filter-branch" or $sub == "bisect")
          and ($args | any(.[]; test("--author")
            or (ascii_downcase | test("user\\.(email|name)"))))
        then "GIT_IDENTITY"
        elif ($sub == "diff" or $sub == "show"
            or ($sub == "log" and ($args | any(.[]; . == "--patch"
              or (test("^-[A-Za-z0-9]") and (.[1:] | cluster_flags("GSOnL") | test("[pu]")))))))
          and (($args | any(.[]; . == "--no-ext-diff")) | not)
        then "EXTDIFF"
        else empty end
      end
    end;
  # GIT_AUTHOR_* / GIT_COMMITTER_* override identity without touching any config.
  # They reach a command as an assignment prefix or an export (both Assign nodes
  # in the AST), or as a plain word when passed through env.
  # Assign nodes carry no Type field, so they are matched by shape: the exact
  # variable name that follows is what makes the match meaningful.
  ([.. | objects | .Name?.Value?]
    | .[]
    | select(type == "string")
    | select(test("^GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)$"))
    | "GIT_IDENTITY"),
  ([.. | objects | select(.Type? == "CallExpr") | [.Args[]? | word_text]]
    | .[]
    | .[]
    | select(test("^GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)="))
    | "GIT_IDENTITY"),
  ([.. | objects | select(.Type? == "CallExpr") | [.Args[]? | word_text]]
  | .[]
  | strip_wrappers
  | select(length > 0)
  | .[0] as $c
  | .[1:] as $a
  | if $c == "rm" then "RM"
    elif $c == "eval" then "EVAL"
    elif $c == "shred" then "SHRED"
    elif ($c | startswith("mkfs.")) then "MKFS"
    elif $c == "dd" and ($a | any(.[]; startswith("of=/dev/"))) then "DD_DEV"
    elif $c == "chmod" then
      # In --reference mode there is no numeric mode argument at all: any
      # "777" is a filename (the reference file or a target path).
      (if ($a | opts_before_ddash | any(.[]; is_abbrev_of("--reference"; 5))) then empty
        elif ($a | any(.[]; . == "777" or . == "0777")) | not then empty
        elif ($a | opts_before_ddash | any(.[]; test("^-[a-zA-Z]*R") or is_abbrev_of("--recursive"; 5)))
        then "CHMOD_R_777"
        elif ($a | any(.[]; . == "/")) then "CHMOD_777_ROOT"
        else empty end)
    elif ($c == "grep" or $c == "egrep" or $c == "fgrep") and ($a | grep_recursive)
    then "GREP_R"
    elif $c == "git" then ($a | git_verdict)
    else empty end)
'
if ! verdicts=$(printf '%s\n' "$CMD" | shfmt --tojson 2>/dev/null | jq -r "$analyze" 2>/dev/null); then
  echo "banned-commands hook could not parse this command as bash (syntax error, or shfmt/jq unavailable); refusing to run it unchecked. Fix the command and retry." >&2
  exit 2
fi

if [[ -n $verdicts ]]; then
  case $(printf '%s\n' "$verdicts" | head -n1) in
  RM) msg="Use gomi instead of rm" ;;
  EVAL) msg="Refuse eval. Review the command and run it directly instead." ;;
  SHRED) msg="Refuse shred. Confirm intent and run manually." ;;
  MKFS) msg="Refuse mkfs. Run manually if intentional." ;;
  DD_DEV) msg="Refuse dd writing to a device. Run manually if intentional." ;;
  CHMOD_R_777) msg="Refuse chmod -R 777. Use a tighter mode." ;;
  CHMOD_777_ROOT) msg="Refuse chmod 777 /. Scope the path." ;;
  GREP_R) msg="Use rg instead of grep -r/-R (recursive grep). rg respects .gitignore and ~/.ripgreprc glob excludes." ;;
  FORCE_PUSH) msg="Refuse git push -f/--force. Use --force-with-lease or run manually." ;;
  GIT_CLEAN) msg="Refuse git clean -fd/-fx (destructive). Inspect untracked files first." ;;
  GIT_RESET_HARD) msg="Refuse git reset --hard to a remote/historical ref. Confirm intent and run manually." ;;
  SHALLOW) msg="Refuse shallow git fetch/pull (--depth/--shallow-*) because it makes the existing repository shallow. Use a temporary shallow clone (git clone --depth), or fetch normally. --deepen/--unshallow remain allowed." ;;
  GIT_IDENTITY) msg="Don't set or override Git identity. ~/.config/git/config.local resolves it per directory via includeIf, and user.useConfigOnly makes Git fail loudly where no entry matches. Ask the user instead of choosing a value." ;;
  EXTDIFF) msg="Add --no-ext-diff to git diff/show/log -p. The global git config sets diff.external=difft, which mangles diff output when captured as tool output; --no-ext-diff is the only reliable bypass (an empty diff.external= override errors out)." ;;
  *) msg="banned-commands hook produced an unknown verdict; refusing to run the command unchecked." ;;
  esac
  printf '%s\n' "$msg" >&2
  exit 2
fi
