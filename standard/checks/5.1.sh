#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

status=0
selector=scripts/apps/dotnet-affected-test.sh
selector_ci=.github/workflows/affected-selector-ci.yml

require() {
  local requirement="$1" description="$2"
  shift 2
  if "$@"; then
    echo "CHECK 5.1 $requirement PASS $description"
  else
    echo "CHECK 5.1 $requirement FAIL $description"
    status=1
  fi
}

contains() { grep -qE -- "$1" "$2" 2> /dev/null; }
trigger_count() { awk -v event="$1" '$0 ~ "^  " event ":" {inside = 1; next} inside && /^  [a-z_]+:/ {inside = 0} inside && /dotnet-affected-test|tests\/\*\*/ {count++} END {print count + 0}' "$selector_ci"; }
triggers_on_selector_and_harness() { [ "$(trigger_count push)" -ge 2 ] && [ "$(trigger_count pull_request)" -ge 2 ]; }
mutant_rows() { sed -n '/<<.MUTANTS./,/^ *MUTANTS$/p' "$selector_ci" | grep -cE '^ *[a-z][a-z0-9-]*\|'; }
has_three_mutants() { [ "$(mutant_rows)" -ge 3 ]; }
harness_runs_ci_selector() { grep -q 'verify-affected-graph.sh' "$selector_ci" && grep -qE 'SELECTOR_SH:-.*scripts/apps/dotnet-affected-test.sh' tests/verify-affected-graph.sh; }
pipeline_runs_the_same_selector() { grep -q 'scripts/apps/dotnet-affected-test.sh' .github/actions/run-affected-tests/action.yml; }

require a "selector has the fail-closed block" contains 'Unmappable non-documentation change detected; selecting FULL test suite' "$selector"
require a "selector widens to the full suite on shared build configuration" contains 'Shared configuration modified; selecting all test suites' "$selector"
require b "push base reference uses github.event.before guarded for new branches" contains "github.event.before != '0000000000000000000000000000000000000000'" .github/workflows/sdet-ci.yml
require c "$selector_ci triggers on push and pull_request for the selector and the harness" triggers_on_selector_and_harness
require c "harness runs the selector script the pipeline executes" harness_runs_ci_selector
require c "pipeline action executes $selector" pipeline_runs_the_same_selector
require d "$selector_ci carries a mutation table with at least three mutants" has_three_mutants
exit "$status"
