#!/usr/bin/env bash
# eval.sh — pipe JavaScript (Omni Automation) to OmniFocus via osascript.
#
# Usage:
#   scripts/eval.sh                  # read JS from stdin
#   scripts/eval.sh path/to/query.js # read JS from file
#
# Exit codes:
#   0       success
#   2       usage error (bad args, file not found)
#   3       OmniFocus could not be launched or did not become responsive
#   other   osascript / Omni Automation error (passed through)
#
# Implementation note: osascript's -l JavaScript mode is JXA, which does NOT
# expose Omni Automation globals (flattenedTasks, inbox, etc.). To reach the
# Omni Automation API we bridge through AppleScript's `evaluate javascript`,
# which runs the JS inside OmniFocus's own scripting engine.

set -euo pipefail

# Resolve source: stdin or single positional file arg.
if [[ $# -eq 0 ]]; then
  src=$(cat)
elif [[ $# -eq 1 ]]; then
  if [[ ! -f "$1" ]]; then
    echo "eval.sh: file not found: $1" >&2
    exit 2
  fi
  src=$(cat "$1")
else
  echo "eval.sh: too many arguments. Usage: eval.sh [file.js] (or pipe JS via stdin)" >&2
  exit 2
fi

# Ensure OmniFocus is running. Launch in the background (no focus steal) and
# wait for the Omni Automation engine to become responsive before proceeding.
if ! pgrep -x OmniFocus >/dev/null 2>&1; then
  open -ga OmniFocus || {
    echo "eval.sh: failed to launch OmniFocus (open -ga returned non-zero)." >&2
    exit 3
  }
  ready=0
  for _ in $(seq 1 60); do
    if osascript -e 'tell application "OmniFocus" to evaluate javascript "1"' >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.5
  done
  if [[ $ready -ne 1 ]]; then
    echo "eval.sh: OmniFocus launched but did not become responsive within 30s." >&2
    exit 3
  fi
fi

# Escape JS for embedding in an AppleScript string literal.
# Order matters: backslashes first, then double quotes, then newlines.
escaped=${src//\\/\\\\}
escaped=${escaped//\"/\\\"}
escaped=${escaped//$'\n'/\\n}

# Bridge to Omni Automation via AppleScript's `evaluate javascript`.
exec osascript -e "tell application \"OmniFocus\" to evaluate javascript \"$escaped\""
