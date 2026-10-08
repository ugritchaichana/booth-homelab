#!/usr/bin/env bash
set -euo pipefail

api="${GITHUB_API_URL:-https://api.github.com}"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -r -f "$work"' EXIT

fetch() {
  printf 'Authorization: Bearer %s\n' "$2" | curl -sS -o "$3" -w '%{http_code}' --max-time 15 -H @- \
    -H 'Accept: application/vnd.github+json' "$1" 2> "$3.err" || true
}

why() {
  local message
  message="$(jq -r '.message? // empty' "$1" 2> /dev/null | head -c 200 || true)"
  echo "${message:-$(head -c 200 "$1.err" 2> /dev/null || true)}"
}

attempt="${RUN_ATTEMPT:-1}"
previous_fingerprint=""
previous_error=""
if [ "$FORCED_HOSTED" != true ] && [ "$attempt" -gt 1 ]; then
  previous=$((attempt - 1))
  code="$(fetch "$api/repos/$REPOSITORY/actions/runs/$RUN_ID/attempts/$previous/jobs?per_page=100" "$GH_TOKEN" "$work/jobs.json")"
  if [ "$code" = 200 ]; then
    mkdir -p "$work/annotations"
    while read -r id; do
      [ -n "$id" ] || continue
      code="$(fetch "$api/repos/$REPOSITORY/check-runs/$id/annotations" "$GH_TOKEN" "$work/annotations/$id.json")"
      if [ "$code" != 200 ]; then
        previous_error="annotations of attempt $previous returned HTTP $code"
        echo "select-runner: $previous_error: $(why "$work/annotations/$id.json")"
      fi
    done < <(jq -r '.jobs[] | select(.conclusion == "failure") | .id' "$work/jobs.json" | tr -d '\r')
    if [ -z "$previous_error" ]; then
      classified="$(python3 "$here/runner_route.py" classify --jobs "$work/jobs.json" --annotations-dir "$work/annotations")"
      echo "select-runner: attempt $previous classified: $(tr '\n' ' ' <<< "$classified")"
      previous_fingerprint="$(sed -n 's/^fingerprint=//p' <<< "$classified")"
    fi
  else
    previous_error="jobs of attempt $previous returned HTTP $code"
    echo "select-runner: $previous_error: $(why "$work/jobs.json")"
  fi
fi

token_present=false
http_status=0
if [ "$FORCED_HOSTED" != true ] && [ -z "$previous_fingerprint" ] && [ -n "${RUNNER_STATUS_TOKEN:-}" ]; then
  token_present=true
  http_status="$(fetch "$api/repos/$REPOSITORY/actions/runners?per_page=100" "$RUNNER_STATUS_TOKEN" "$work/runners.json")"
  [ "$http_status" = 200 ] || echo "select-runner: runner health check returned HTTP $http_status: $(why "$work/runners.json")"
fi

decision="$(python3 "$here/runner_route.py" decide --forced-hosted "$FORCED_HOSTED" --token-present "$token_present" \
  --http-status "$http_status" --runners "$work/runners.json" \
  --previous-fingerprint "$previous_fingerprint" --previous-error "$previous_error")"
hosted="$(sed -n 's/^hosted=//p' <<< "$decision")"
reason="$(sed -n 's/^reason=//p' <<< "$decision")"

if [ "$hosted" = true ]; then
  label='GitHub-Hosted (ubuntu-latest)'
  {
    echo 'hosted=true'
    echo 'dotnet_labels=["ubuntu-latest"]'
    echo 'angular_labels=["ubuntu-latest"]'
  } >> "$GITHUB_OUTPUT"
else
  label='Proxmox VE Self-Hosted (LXC)'
  {
    echo 'hosted=false'
    echo 'dotnet_labels=["self-hosted", "linux", "proxmox", "dotnet"]'
    echo 'angular_labels=["self-hosted", "linux", "proxmox", "angular"]'
  } >> "$GITHUB_OUTPUT"
fi
{
  echo "runner_label=$label"
  echo "route_reason=$reason"
} >> "$GITHUB_OUTPUT"
echo "Runner route (attempt $attempt): $label because $reason"
echo "**Runner route (attempt $attempt):** $label because $reason" >> "$GITHUB_STEP_SUMMARY"
