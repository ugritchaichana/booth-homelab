#!/usr/bin/env bash
# Usage: assert-cache-telemetry.sh <log-file> <reported-value>
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <log-file> <reported-value>" >&2
    exit 2
fi

LOG_FILE="$1"
REPORTED_VALUE="$2"

if [ ! -f "$LOG_FILE" ]; then
    echo "::error::Cache telemetry assertion cannot read log file '$LOG_FILE'."
    exit 2
fi

if grep -q '^\[CACHE HIT\]' "$LOG_FILE"; then
    MARKER_PRESENT=true
else
    MARKER_PRESENT=false
fi

if [ "$MARKER_PRESENT" = "true" ] && [ "$REPORTED_VALUE" != "true" ]; then
    echo "::error::Cache telemetry mismatch: log contains [CACHE HIT] but the reported value is '${REPORTED_VALUE}'."
    exit 1
fi

if [ "$MARKER_PRESENT" = "false" ] && [ "$REPORTED_VALUE" = "true" ]; then
    echo "::error::Cache telemetry mismatch: reported value is 'true' but the log has no [CACHE HIT] marker."
    exit 1
fi

echo "Cache telemetry consistent: marker present=${MARKER_PRESENT}, reported=${REPORTED_VALUE:-<empty>}."
