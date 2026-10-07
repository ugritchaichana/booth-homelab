#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundles="$repo/iac/ansible/roles/pve_templates/files/bundles"
lint="$repo/tests/isolation/lib/lint-template-content.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$3', wanted '$2'"; failures=$((failures + 1)); fi
}

command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook is not installed" >&2; exit 2; }

echo "== every shipped bundle passes the content rules"
rc=0; python3 -I "$lint" "$bundles" > "$work/real.log" 2>&1 || rc=$?
expect "the shipped bundles lint clean" 0 "$rc"
cat "$work/real.log"

echo "== mutation: an artifact without its hash is refused"
cp -r "$bundles" "$work/mutant"
sed -i '0,/^    sha512: /{/^    sha512: /d}' "$work/mutant/lxc-runner/versions.yml"
rc=0; python3 -I "$lint" "$work/mutant" > "$work/mutant.log" 2>&1 || rc=$?
expect "the linter exits 1 on a dropped hash" 1 "$rc"
expect "the finding names the artifact" 1 "$(grep -c 'artifact dotnet_sdk_8 has no valid sha256 or sha512 pin' "$work/mutant.log" || true)"

echo "== the class playbook parses"
rc=0
ANSIBLE_LOCALHOST_WARNING=False ansible-playbook --syntax-check -i localhost, -e build_id=syntax-check "$bundles/lxc-runner/playbook.yml" > "$work/syntax.log" 2>&1 || rc=$?
expect "ansible-playbook --syntax-check exits 0" 0 "$rc"
[ "$rc" -eq 0 ] || cat "$work/syntax.log"

if [ "$failures" -ne 0 ]; then echo "FAILED: $failures check(s)"; exit 1; fi
echo "OK: template content bundles are pinned and the lxc-runner playbook parses"
