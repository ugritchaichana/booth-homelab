#!/usr/bin/env bash
# Job-completed hook: asks root to restart this listener, which otherwise stalls about 60 s before its next job (actions/runner#4444).
instance="${RUNNER_NAME##*-}"
if [[ "$instance" =~ ^[0-9]+$ ]] && [ -d "/run/actions-runner-$instance" ]; then
  touch "/run/actions-runner-$instance/restart" || true
fi
exit 0
