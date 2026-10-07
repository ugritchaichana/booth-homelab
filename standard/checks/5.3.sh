#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

pipeline=.github/workflows/reusable-sdet-pipeline.yml
asserting_files=$(find scripts/ci -maxdepth 1 -name 'assert-cache-telemetry*' 2> /dev/null | head -1)

if grep -q 'assert-cache-telemetry' "$pipeline" 2> /dev/null; then
  echo "CHECK 5.3 b PASS assert-cache-telemetry is wired into $pipeline"
  exit 0
fi
if [ -n "$asserting_files" ]; then
  echo "CHECK 5.3 b FAIL $asserting_files exists but $pipeline does not call it"
  exit 1
fi
echo "CHECK 5.3 b INFO assert-cache-telemetry does not exist yet; telemetry assertion unmeasured"
echo "CHECK 5.3 a INFO summary-versus-log agreement over consecutive runs is a run record, not scanned here"
exit 0
