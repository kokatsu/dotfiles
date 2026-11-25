#!/usr/bin/env bash
# Entry point for report-agent-session, shared by the Claude Code and Codex
# SessionStart hooks.
#
# Usage: report-agent-session.sh session <claude|codex>
#
# Every check lives in the binary. This only keeps the hook from failing when
# the binary is missing: nothing that stops the report may stop the session from
# starting.

command -v report-agent-session >/dev/null 2>&1 || exit 0
report-agent-session "$@"
exit 0
