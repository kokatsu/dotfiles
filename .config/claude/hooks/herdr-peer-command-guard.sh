#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Match literal Herdr input commands at shell-command boundaries, including
# control-flow keywords and common command wrappers. This is a best-effort
# guardrail rather than a security boundary: arbitrary Bash can still obscure
# a command or access the socket directly.
shell_word_re='[^;&|(){}[:space:]]+'
wrapper_option_re='--?[^;&|(){}[:space:]]+'
wrapper_argument_re='[^;&|(){}[:space:]-][^;&|(){}[:space:]]*'
wrapper_name_re="([^;&|(){}[:space:]]*/)?(env|command|exec|xargs|sudo|nohup|time|builtin)"
wrapper_re="${wrapper_name_re}[[:space:]]+(($wrapper_option_re)[[:space:]]+(($wrapper_argument_re)[[:space:]]+)?)*"
control_re='((then|do|else|elif|if|while|until|!)[[:space:]]+)*'
herdr_input_re=$'(^|[;&|(){}\n])[[:space:]]*'"${control_re}(${wrapper_re}|[A-Za-z_][A-Za-z0-9_]*=${shell_word_re}[[:space:]]+)*([^;&|(){}[:space:]]*/)?herdr[[:space:]]+(agent[[:space:]]+(prompt|send-keys)|pane[[:space:]]+(send-text|send-keys|run))([;&|(){}[:space:]]|$)"

if [[ $command_text =~ $herdr_input_re ]]; then
  echo "Use herdr-peer instead of raw Herdr input commands so the same-tab peer checks are applied." >&2
  exit 2
fi
