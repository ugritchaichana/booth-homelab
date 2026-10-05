#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

status=0
require() {
  local requirement="$1" description="$2"
  shift 2
  if "$@"; then
    echo "CHECK 5.5 $requirement PASS $description"
  else
    echo "CHECK 5.5 $requirement FAIL $description"
    status=1
  fi
}

contains() { grep -qE -- "$1" "$2" 2> /dev/null; }
runner_config_count() { find apps/backend/tests -name xunit.runner.json -exec grep -l '"maxParallelThreads"' {} + 2> /dev/null | wc -l | tr -d ' '; }
test_project_count() { find apps/backend/tests -name '*.csproj' | wc -l | tr -d ' '; }
every_test_project_is_bounded() { [ "$(test_project_count)" -gt 0 ] && [ "$(runner_config_count)" -eq "$(test_project_count)" ]; }

require b "apps/frontend/jest.config.js sets maxWorkers" contains '^[[:space:]]*maxWorkers:' apps/frontend/jest.config.js
require b "apps/frontend/jest.config.js sets workerIdleMemoryLimit" contains '^[[:space:]]*workerIdleMemoryLimit:' apps/frontend/jest.config.js
require b "every test project under apps/backend/tests has an xunit.runner.json with maxParallelThreads" every_test_project_is_bounded
require c "apps/README.md states the flaky-test policy heading" contains '^## Flaky tests' apps/README.md
require c "apps/README.md sets the 24 hour quarantine window" contains 'Within 24 hours.*quarantined' apps/README.md
require c "apps/README.md names the 20 consecutive repeat runs to return" contains '20 consecutive green repeat runs' apps/README.md
echo "CHECK 5.5 a INFO repeat runs of each suite are a drill record, not scanned here"
exit "$status"
