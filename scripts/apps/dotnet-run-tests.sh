#!/usr/bin/env bash
set -euo pipefail

LIST="${1:?usage: dotnet-run-tests.sh LIST_FILE [RESULTS_DIR]}"
RESULTS="${2:-apps/backend/TestResults}"
CONFIGURATION="${CONFIGURATION:-Release}"
mkdir -p "$RESULTS"

rc=0
ran=0
while IFS= read -r project || [ -n "$project" ]; do
    project="${project%$'\r'}"
    [ -n "$project" ] || continue
    name="$(basename "$project" .csproj)"
    dll="$(find "$(dirname "$project")/bin/$CONFIGURATION" -mindepth 2 -maxdepth 2 -name "$name.dll" 2>/dev/null | sort | head -1 || true)"
    if [ -z "$dll" ]; then
        echo "::error::no built $name.dll under $(dirname "$project")/bin/$CONFIGURATION"
        rc=1
        continue
    fi
    echo "==> $name ($dll)"
    dotnet test "$dll" --logger "trx;LogFileName=$name.trx" --results-directory "$RESULTS" || rc=1
    ran=$((ran + 1))
done < "$LIST"

echo "[Suites] ran $ran from $LIST"
exit "$rc"
