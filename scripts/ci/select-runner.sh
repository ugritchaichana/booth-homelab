#!/usr/bin/env bash
set -euo pipefail
: "${REPOSITORY:?}" "${RUN_ID:?}" "${FORCED_HOSTED:?}"
# shellcheck source=scripts/ci/attempt-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/attempt-lib.sh"
work="$(mktemp -d)"
trap 'rm -r -f "$work"' EXIT

attempt="${RUN_ATTEMPT:-1}"
classified=""
if [ "$FORCED_HOSTED" != true ] && [ "$attempt" -gt 1 ]; then
  classified="$(classify_attempt "$RUN_ID" $((attempt - 1)) "$work/previous")"
  echo "select-runner: attempt $((attempt - 1)) classified: $(tr '\n' ' ' <<< "$classified")"
fi
previous_env="$(attempt_env "$classified")"

token_present=false
http_status=0
if [ "$FORCED_HOSTED" != true ] && [ "$previous_env" != proxmox ] && [ -n "${RUNNER_STATUS_TOKEN:-}" ]; then
  token_present=true
  http_status="$(fetch "$api/repos/$REPOSITORY/actions/runners?per_page=100" "$RUNNER_STATUS_TOKEN" "$work/runners.json")"
  [ "$http_status" = 200 ] || echo "select-runner: runner health check returned HTTP $http_status: $(why "$work/runners.json")"
fi

decision="$(python3 "$lib_dir/runner_route.py" decide --forced-hosted "$FORCED_HOSTED" --token-present "$token_present" --http-status "$http_status" --runners "$work/runners.json" --previous-env "$previous_env" --previous-cause "$(field cause "$classified")" --previous-error "$(field error "$classified")")"
hosted="$(sed -n 's/^hosted=//p' <<< "$decision")"
reason="$(sed -n 's/^reason=//p' <<< "$decision")"

if [ "$hosted" = true ]; then
  label='GitHub-Hosted (ubuntu-latest)'
  printf '%s\n' 'hosted=true' 'dotnet_labels=["ubuntu-latest"]' 'angular_labels=["ubuntu-latest"]' >> "$GITHUB_OUTPUT"
else
  label='Proxmox VE Self-Hosted (LXC)'
  printf '%s\n' 'hosted=false' 'dotnet_labels=["self-hosted", "linux", "proxmox", "dotnet"]' 'angular_labels=["self-hosted", "linux", "proxmox", "angular"]' >> "$GITHUB_OUTPUT"
fi
printf '%s\n' "runner_label=$label" "route_reason=$reason" >> "$GITHUB_OUTPUT"
echo "Runner route (attempt $attempt): $label because $reason"
echo "**Runner route (attempt $attempt):** $label because $reason" >> "$GITHUB_STEP_SUMMARY"
