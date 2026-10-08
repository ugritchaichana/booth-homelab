#!/usr/bin/env bash
set -euo pipefail
: "${REPOSITORY:?}" "${RUN_ID:?}" "${GH_TOKEN:?}"
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || { echo "sdet-classify: RUN_ID must be a number" >&2; exit 1; }
# shellcheck source=scripts/ci/attempt-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/attempt-lib.sh"
work="$(mktemp -d)"
trap 'rm -r -f "$work"' EXIT

code="$(fetch "$api/repos/$REPOSITORY/actions/runs/$RUN_ID" "$GH_TOKEN" "$work/run.json")"
if [ "$code" != 200 ]; then
  echo "sdet-classify: run $RUN_ID returned HTTP $code: $(why "$work/run.json")"
  exit 1
fi
attempt="$(jq -r '.run_attempt' "$work/run.json" | tr -d '\r')"
conclusion="$(jq -r '.conclusion // ""' "$work/run.json" | tr -d '\r')"
field() { sed -n "s/^$1=//p" <<< "$2"; }

current=""
if [ "$conclusion" = failure ]; then
  current="$(classify_attempt "$RUN_ID" "$attempt" "$work/current")"
fi
previous=""
if [ "$attempt" -gt 1 ]; then
  previous="$(classify_attempt "$RUN_ID" $((attempt - 1)) "$work/previous")"
  current="${current:-$(classify_attempt "$RUN_ID" "$attempt" "$work/current")}"
fi
echo "sdet-classify: run $RUN_ID attempt $attempt $conclusion; this attempt: $(tr '\n' ' ' <<< "$current"); previous: $(tr '\n' ' ' <<< "$previous")"

verdict="$(python3 "$lib_dir/runner_route.py" verdict --attempt "$attempt" --conclusion "$conclusion" \
  --proxmox "$(field proxmox "$current")" --fingerprint "$(field fingerprint "$current")" --error "$(field error "$current")" \
  --previous-fingerprint "$(field fingerprint "$previous")")"
echo "$verdict" >> "$GITHUB_OUTPUT"
echo "sdet-classify: $(tr '\n' ' ' <<< "$verdict")"
note="$(field note "$verdict")"
if [ -n "$note" ]; then
  echo "**Runner:** $note" >> "$GITHUB_STEP_SUMMARY"
fi
