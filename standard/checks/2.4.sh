#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

status=0
name_pattern='[A-Z_]*(PASS|SECRET|TOKEN|KEY)[A-Z_]*'

report_defaults() {
  local label="$1" pattern="$2" hits file line name count=0
  hits=$(grep -rnE "$pattern" scripts/ 2>/dev/null | cut -d: -f1,2 | tr -d '\r')
  if [ -n "$hits" ]; then
    count=$(echo "$hits" | wc -l | tr -d ' ')
    while IFS=: read -r file line; do
      name=$(sed -n "${line}p" "$file" | grep -oE "(getenv|environ\.get)\(\"$name_pattern\"" | head -1)
      echo "CHECK 2.4 b FAIL $file:$line ${name:-default value on a secret-named variable}"
    done <<< "$hits"
  fi
  echo "CHECK 2.4 b $([ "$count" -eq 0 ] && echo PASS || echo FAIL) $label with a default value=$count"
  [ "$count" -eq 0 ] || status=1
}

report_defaults "getenv on a secret-named variable" "getenv\(\"$name_pattern\", *\"[^\"]+\""
report_defaults "environ.get on a secret-named variable" "environ\.get\(\"$name_pattern\", *[\"'][^\"']+[\"']"

for gate in .github/workflows/secret-scan.yml .pre-commit-config.yaml; do
  if grep -qi gitleaks "$gate" 2>/dev/null; then
    echo "CHECK 2.4 c PASS $gate runs gitleaks"
  else
    echo "CHECK 2.4 c FAIL $gate has no gitleaks"
    status=1
  fi
done

if command -v gitleaks > /dev/null 2>&1; then
  report_dir=$(mktemp -d)
  count_findings() { grep -o '"RuleID"' "$1" 2>/dev/null | wc -l | tr -d ' '; }
  gitleaks git --no-banner --redact=100 --exit-code 0 --log-opts=--all --report-format json --report-path "$report_dir/history.json" . > /dev/null 2>&1
  gitleaks dir --no-banner --redact=100 --exit-code 0 --report-format json --report-path "$report_dir/tree.json" . > /dev/null 2>&1
  if [ -f "$report_dir/history.json" ] && [ -f "$report_dir/tree.json" ]; then
    history_count=$(count_findings "$report_dir/history.json")
    tree_count=$(count_findings "$report_dir/tree.json")
    echo "CHECK 2.4 a INFO gitleaks findings in the full history=$history_count"
    if [ "$tree_count" -eq 0 ]; then
      echo "CHECK 2.4 a PASS gitleaks findings in the working tree=0"
    else
      echo "CHECK 2.4 a FAIL gitleaks findings in the working tree=$tree_count"
      status=1
    fi
  else
    echo "CHECK 2.4 a INFO gitleaks ran without writing a report; findings unmeasured"
  fi
  rm -f "$report_dir/history.json" "$report_dir/tree.json"
  rmdir "$report_dir"
else
  echo "CHECK 2.4 a INFO gitleaks not on PATH; history and tree findings unmeasured"
fi
echo "CHECK 2.4 d INFO rotation runbook exercise is a drill record, not scanned here"
exit "$status"
