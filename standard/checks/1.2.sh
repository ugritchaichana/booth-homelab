#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

status=0
fixed_paths=$(grep -rnoE '"/tmp/[A-Za-z]|=/tmp/[A-Za-z]' scripts/ .github/ 2>/dev/null | tr -d '\r')
count=0
if [ -n "$fixed_paths" ]; then
  count=$(echo "$fixed_paths" | wc -l | tr -d ' ')
  while IFS= read -r hit; do
    echo "CHECK 1.2 c FAIL ${hit%%:*}:$(echo "$hit" | cut -d: -f2) $(echo "$hit" | cut -d: -f3-)"
  done <<< "$fixed_paths"
  status=1
fi
if [ "$count" -eq 0 ]; then
  echo "CHECK 1.2 c PASS fixed temp paths (standard regex) over scripts/ and .github/ = 0"
else
  echo "CHECK 1.2 c FAIL fixed temp paths (standard regex) over scripts/ and .github/ = $count"
fi

broad=$(grep -rnoE '/tmp/[A-Za-z]' scripts/ iac/ansible/roles/ 2>/dev/null | tr -d '\r')
broad_count=0
[ -n "$broad" ] && broad_count=$(echo "$broad" | wc -l | tr -d ' ')
echo "CHECK 1.2 c INFO broader /tmp/ scan over scripts/ and iac/ansible/roles/ = $broad_count"
if [ -n "$broad" ]; then
  while IFS= read -r hit; do
    echo "CHECK 1.2 c INFO ${hit%%:*}:$(echo "$hit" | cut -d: -f2) $(echo "$hit" | cut -d: -f3-)"
  done <<< "$broad"
fi
echo "CHECK 1.2 a INFO canary pair and stored-credential listing are drill measurements, not scanned here"
exit "$status"
