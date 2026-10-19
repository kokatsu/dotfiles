#!/usr/bin/env bash
# Entry point for report-agent-session, shared by the Claude Code and Codex
# SessionStart hooks.
#
# Usage: report-agent-session.sh session <claude|codex>
#
# Every check lives in the binary. This only keeps the hook from failing when
# the binary is missing: unlike the cache token, an agent session has no
# "clear" call to fall back on, so nothing that stops the report may stop the
# session from starting.

command -v report-agent-session >/dev/null 2>&1 || exit 0
report-agent-session "$@"
exit 0
