#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

workflow=.github/workflows/iac-ci.yml
report() {
  local requirement="$1" label="$2" pattern="$3" hits
  hits=$(grep -ciE "$pattern" "$workflow" 2>/dev/null)
  echo "CHECK 2.5 $requirement INFO $label in $workflow: $([ "${hits:-0}" -gt 0 ] && echo present || echo absent)"
}

if [ ! -f "$workflow" ]; then
  echo "CHECK 2.5 a INFO $workflow not found"
  exit 0
fi
report a "tflint" 'tflint'
report b "tofu plan" 'tofu[[:space:]]+(-chdir=[^[:space:]]+[[:space:]]+)?plan'
report c "ansible-lint --profile production" 'ansible-lint[^#]*--profile[ =]production'
report c "converge or molecule" 'molecule|converge'
exit 0
