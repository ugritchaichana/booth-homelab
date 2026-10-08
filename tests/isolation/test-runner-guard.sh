#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="${RUNNER_GUARD_SCRIPT:-$repo/scripts/ci/runner-guard.sh}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
[ -f "$guard" ] || { echo "ERROR: no guard at $guard" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 2; }

OWN=example/lab
printf '{"pull_request":{"head":{"repo":{"full_name":"%s"}}}}\n' "$OWN" > "$work/same.json"
printf '{"pull_request":{"head":{"repo":{"full_name":"%s"}}}}\n' "someone/lab" > "$work/fork.json"
printf '{"pull_request":{"head":{"repo":null}}}\n' > "$work/deleted-fork.json"

fails=0
expect() {
  local want=$1 name=$2 rc=0
  shift 2
  env -i PATH="$PATH" "$@" bash "$guard" > "$work/out" 2>&1 || rc=$?
  if { [ "$want" = allow ] && [ "$rc" -eq 0 ]; } || { [ "$want" = deny ] && [ "$rc" -ne 0 ]; }; then
    echo "PASS $name"
  else
    echo "FAIL $name: rc=$rc $(cat "$work/out")"
    fails=$((fails + 1))
  fi
}

base=(RUNNER_GUARD_REPOSITORY=$OWN GITHUB_REPOSITORY=$OWN)
expect allow "a push in the repository runs" "${base[@]}" GITHUB_EVENT_NAME=push
expect allow "a manual dispatch runs" "${base[@]}" GITHUB_EVENT_NAME=workflow_dispatch
expect allow "a schedule runs" "${base[@]}" GITHUB_EVENT_NAME=schedule
expect allow "a pull request from a branch of the repository runs" "${base[@]}" GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$work/same.json"
expect deny "a pull request from a fork is refused" "${base[@]}" GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$work/fork.json"
expect deny "a pull request from a deleted fork is refused" "${base[@]}" GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$work/deleted-fork.json"
expect deny "a pull request without a payload is refused" "${base[@]}" GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$work/missing.json"
expect deny "pull_request_target is refused" "${base[@]}" GITHUB_EVENT_NAME=pull_request_target GITHUB_EVENT_PATH="$work/same.json"
expect deny "an issue comment is refused" "${base[@]}" GITHUB_EVENT_NAME=issue_comment
expect deny "an unset event is refused" "${base[@]}"
expect deny "another repository is refused" RUNNER_GUARD_REPOSITORY=$OWN GITHUB_REPOSITORY=someone/lab GITHUB_EVENT_NAME=push
expect deny "a runner without its allowed repository refuses everything" GITHUB_REPOSITORY=$OWN GITHUB_EVENT_NAME=push

env -i PATH="$PATH" RUNNER_GUARD_REPOSITORY=$OWN GITHUB_REPOSITORY=$OWN GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$work/fork.json" bash "$guard" > "$work/out" 2>&1 || true
grep -q 'refused: pull request from someone/lab' "$work/out" && echo "PASS a refusal names the fork in the job log" || { echo "FAIL refusal message: $(cat "$work/out")"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] || { echo "$fails failure(s)"; exit 1; }
echo "all runner guard cases passed"
