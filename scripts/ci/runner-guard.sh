#!/usr/bin/env bash
set -euo pipefail

# Job-started hook of the self-hosted runner (ACTIONS_RUNNER_HOOK_JOB_STARTED): a non-zero exit fails the job before any step runs.
deny() { echo "runner-guard: refused: $*" >&2; exit 1; }

allowed="${RUNNER_GUARD_REPOSITORY:-}"
[ -n "$allowed" ] || deny "RUNNER_GUARD_REPOSITORY is not set on the runner"
[ "${GITHUB_REPOSITORY:-}" = "$allowed" ] || deny "repository ${GITHUB_REPOSITORY:-unset}"

case "${GITHUB_EVENT_NAME:-}" in
  push | workflow_dispatch | schedule) ;;
  pull_request)
    [ -r "${GITHUB_EVENT_PATH:-}" ] || deny "pull request without a readable event payload"
    head="$(jq -r '.pull_request.head.repo.full_name // empty' "$GITHUB_EVENT_PATH")"
    [ "$head" = "$allowed" ] || deny "pull request from ${head:-an unknown repository}"
    ;;
  *) deny "event ${GITHUB_EVENT_NAME:-unset}" ;;
esac

echo "runner-guard: allowed ${GITHUB_EVENT_NAME} on ${GITHUB_REPOSITORY}"
