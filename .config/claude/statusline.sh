#!/usr/bin/env bash
# Status line: cc-statusline, with the Fable weekly row that the fable-usage
# mod caches appended to its last row. Before the first response cc-statusline
# prints no rate-limit row, so the Fable row goes on a row of its own.
set -u

line=$(CC_STATUSLINE_SHOW_COST=0 cc-statusline)
fable=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/claude-fable-usage" 2>/dev/null)

printf '%s' "$line"
if [[ -n $fable ]]; then
  if [[ $line == *$'\n'* ]]; then
    # cc-statusline's own separator color
    printf ' \033[38;2;108;112;134m|\033[0m %s' "$fable"
  else
    printf '\n%s' "$fable"
  fi
fi
echo
