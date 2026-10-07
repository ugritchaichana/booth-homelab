#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${PVE_API_IDENTITY_ROLE_DIR:-$repo/iac/ansible/roles/pve_api_identity}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook is not installed" >&2; exit 2; }
[ -f "$role/tasks/assert.yml" ] || { echo "ERROR: no tasks/assert.yml under $role" >&2; exit 2; }
grep -q 'import_tasks: assert.yml' "$role/tasks/main.yml" || { echo "FAIL: tasks/main.yml does not run assert.yml" >&2; exit 1; }

cat > "$work/play.yml" <<'YML'
---
- name: Evaluate the declared roles and grants of the provisioner identity
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Run the role assertions only
      ansible.builtin.include_role:
        name: pve_api_identity
        tasks_from: assert
YML

ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
  ANSIBLE_ROLES_PATH="$(dirname "$role")" \
  ansible-playbook "$work/play.yml" > "$work/ansible.log" 2>&1 \
  || { cat "$work/ansible.log" >&2; echo "FAIL: the declared roles or grants break the clone-only rule" >&2; exit 1; }

cat > "$work/cache-play.yml" <<'YML'
---
- name: Evaluate the SDN grants of the provisioner identity
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Load the role defaults
      ansible.builtin.include_role:
        name: pve_api_identity
        tasks_from: assert
        public: true
    - name: Assert the vnet grants
      ansible.builtin.assert:
        that:
          - pve_api_identity_grants | selectattr('path', 'match', '^/sdn/zones/hlab/') | map(attribute='path') | sort | list == expected_paths
          - pve_api_identity_grants | selectattr('path', 'match', '^/sdn/zones/hlab/') | map(attribute='role') | unique | list == ['HomelabGuestNetwork']
          - pve_api_identity_grants | length == base_count + (expected_paths | length - 1)
YML

grant_case() {
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
    ANSIBLE_ROLES_PATH="$(dirname "$role")" \
    ansible-playbook "$work/cache-play.yml" -e "$1" > "$work/ansible.log" 2>&1 \
    || { cat "$work/ansible.log" >&2; echo "FAIL: $2" >&2; exit 1; }
}
grant_case '{"expected_paths": ["/sdn/zones/hlab/guests"], "base_count": 8}' "a host without cache_network must grant only the guest vnet and add no entry"
grant_case '{"cache_network": {"vnet": "cache"}, "expected_paths": ["/sdn/zones/hlab/cache", "/sdn/zones/hlab/guests"], "base_count": 8}' "a host with cache_network must grant the cache vnet path with exactly the guest vnet role"

echo "OK: VM.Clone only on the templates pool, nothing else granted there; the cache vnet is granted only when declared"
