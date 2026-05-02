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
#   3       OmniFocus is not running
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

# Verify OmniFocus is running. Do not auto-launch.
if ! pgrep -x OmniFocus >/dev/null 2>&1; then
  echo "eval.sh: OmniFocus is not running. Launch it and retry." >&2
  exit 3
fi

# Escape JS for embedding in an AppleScript string literal.
# Order matters: backslashes first, then double quotes, then newlines.
escaped=${src//\\/\\\\}
escaped=${escaped//\"/\\\"}
escaped=${escaped//$'\n'/\\n}

# Bridge to Omni Automation via AppleScript's `evaluate javascript`.
exec osascript -e "tell application \"OmniFocus\" to evaluate javascript \"$escaped\""
