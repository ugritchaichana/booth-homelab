#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

hosted_label='^["'"'"']?(ubuntu|windows|macos)-[A-Za-z0-9.-]+["'"'"']?$'
status=0
triggered=0

runs_on_blocks() {
  tr -d '\r' < "$1" | awk -v file="$1" '
    function flush() { if (inside) { gsub(/[[:space:]]+/, " ", buf); print file ":" start ":" buf; inside = 0 } }
    /^[[:space:]]*runs-on:/ { flush(); match($0, /^[[:space:]]*/); indent = RLENGTH; buf = $0; sub(/^[[:space:]]*runs-on:[[:space:]]*/, "", buf); start = FNR; inside = 1; next }
    inside { match($0, /^[[:space:]]*/); if (length($0) > RLENGTH && RLENGTH > indent) { buf = buf " " $0 } else { flush() } }
    END { flush() }'
}

for workflow in $(grep -l 'pull_request_target' .github/workflows/*.yml 2>/dev/null); do
  triggered=$((triggered + 1))
  while IFS= read -r block; do
    location="${block%%:*}:$(echo "$block" | cut -d: -f2)"
    labels="$(echo "$block" | cut -d: -f3- | sed -E 's/^ +//; s/ +$//')"
    if echo "$labels" | grep -qE "$hosted_label"; then
      echo "CHECK 1.1 b PASS $location runs-on=$labels"
    else
      echo "CHECK 1.1 b FAIL $location runs-on=$labels"
      status=1
    fi
  done < <(runs_on_blocks "$workflow")
  for call in $(grep -nE '^[[:space:]]*uses:[[:space:]]*\./\.github/workflows/' "$workflow" | cut -d: -f1); do
    echo "CHECK 1.1 b FAIL $workflow:$call calls a local reusable workflow; its runner label is not provable here"
    status=1
  done
done
[ "$triggered" -eq 0 ] && echo "CHECK 1.1 b PASS no workflow uses pull_request_target"

ephemeral_hits=$(grep -rcE -- 'generate-jitconfig' scripts/proxmox/ephemeral 2>/dev/null | awk -F: '{sum += $2} END {print sum + 0}')
echo "CHECK 1.1 a INFO generate-jitconfig occurrences in scripts/proxmox/ephemeral=$ephemeral_hits"

visibility=""
if [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && command -v gh > /dev/null 2>&1; then
  visibility=$(gh api "repos/$GITHUB_REPOSITORY" --jq .visibility 2>/dev/null || true)
fi
if [ -n "$visibility" ]; then
  echo "CHECK 1.1 a INFO repository visibility=$visibility"
else
  echo "CHECK 1.1 a INFO repository visibility unmeasured (needs GH_TOKEN and GITHUB_REPOSITORY)"
fi
echo "CHECK 1.1 c INFO fork pull-request approval policy unmeasured (needs an administration-read token)"
exit "$status"
