#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

claim_pattern='[0-9]+(\.[0-9]+)? ?(MiB/s|GB/s|ms|min|%)|v[0-9]+\.[0-9]+\.[0-9]+|Zero-Trust|Enterprise|SOC ?2|ISO.?27001'
repo_url='https://github\.com/ugritchaichana/booth-homelab'
run_link="^${repo_url}/actions/runs/[0-9]+(/job/[0-9]+|/attempts/[0-9]+)?\$"
evidence_link="^((\\.{1,2}/)*|${repo_url}/(blob|tree)/[A-Za-z0-9._-]+/)standard/evidence/[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}(-ack)?\\.md(#[A-Za-z0-9_-]+)?\$"
blob_link="^${repo_url}/blob/([0-9a-f]{40})/([^#[:space:]]+)#L[0-9]+(-L[0-9]+)?\$"

is_backing_link() {
  local target="$1" evidence_path
  if [[ "$target" =~ $run_link ]]; then
    return 0
  fi
  if [[ "$target" =~ $evidence_link ]]; then
    evidence_path="standard/evidence/${target#*standard/evidence/}"
    [ -f "${evidence_path%%#*}" ]
    return
  fi
  if [[ "$target" =~ $blob_link ]]; then
    [ -e .git ] || return 0
    git cat-file -e "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}" 2> /dev/null
    return
  fi
  return 1
}

hits=$(grep -rnE "$claim_pattern" README.md wiki/ AGENTS.md AI_CONTEXT.md 2>/dev/null | tr -d '\r' | LC_ALL=C sort -t: -k1,1 -k2,2n)
total=0
unbacked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  total=$((total + 1))
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  text="${rest#*:}"
  backed=0
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    target="${link#](}"
    target="${target%)}"
    if is_backing_link "$target"; then
      backed=1
      break
    fi
  done < <(echo "$text" | grep -oE '\]\([^)]*\)')
  if [ "$backed" -eq 0 ]; then
    unbacked=$((unbacked + 1))
    echo "CHECK 4.2 b FAIL $file:$line token=$(echo "$text" | grep -oE "$claim_pattern" | head -1)"
  fi
done <<< "$hits"

echo "CHECK 4.2 a INFO claim hits=$total"
if [ "$unbacked" -eq 0 ]; then
  echo "CHECK 4.2 b PASS unbacked=0"
  exit 0
fi
echo "CHECK 4.2 b FAIL unbacked=$unbacked"
exit 1
