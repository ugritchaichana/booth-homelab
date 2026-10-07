#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gate="${CACHE_START_GATE_FILE:-$repo/iac/ansible/playbooks/tasks/cache-start-gate.yml}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible-playbook >/dev/null || { echo "ERROR: ansible is not installed" >&2; exit 2; }
[ -f "$gate" ] || { echo "ERROR: no gate file at $gate" >&2; exit 2; }

mkdir -p "$work/bin"
cat > "$work/bin/pvesh" <<'SH'
#!/usr/bin/env bash
case "$2" in
  */firewall/options) cat "$STUB_DIR/options.json" ;;
  */firewall/rules) cat "$STUB_DIR/rules.json" ;;
  */config) cat "$STUB_DIR/config.json" ;;
  *) exit 2 ;;
esac
SH
cat > "$work/bin/pct" <<'SH'
#!/usr/bin/env bash
case "$1" in
  status) echo "status: $(cat "$STUB_DIR/status")" ;;
  start) echo "start $2" >> "$STUB_DIR/calls" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$work/bin/pvesh" "$work/bin/pct"
export STUB_DIR="$work" PATH="$work/bin:$PATH"

cat > "$work/play.yml" <<EOF
---
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    cache_vmid: 9050
    cache_node: pve01
    cache_vnet: cache
  tasks:
    - ansible.builtin.include_tasks: "$gate"
EOF

good_options='{"enable": 1, "policy_in": "DROP", "policy_out": "DROP", "ipfilter": 1, "macfilter": 1}'
good_rules='[{"type": "group", "action": "guest-egress", "enable": 1, "pos": 0}, {"type": "group", "action": "cache-ingress", "enable": 1, "pos": 1}]'
good_config='{"net0": "name=eth0,bridge=cache,firewall=1,gw=10.99.17.1,hwaddr=BC:24:11:00:00:01,ip=10.99.17.10/24,type=veth", "unprivileged": 1}'

setup() {
  printf '%s' "$1" > "$work/options.json"
  printf '%s' "$2" > "$work/rules.json"
  printf '%s' "$3" > "$work/config.json"
  printf '%s' "${4:-stopped}" > "$work/status"
  : > "$work/calls"
}

run_gate() {
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
    ansible-playbook -i localhost, "$work/play.yml" > "$work/ansible.log" 2>&1
}

check_all() {
  local failures=0 label
  setup "$good_options" "$good_rules" "$good_config"
  if run_gate && grep -qx "start 9050" "$work/calls"; then echo "ok: a compliant stopped container is started"; else echo "FAIL: a compliant stopped container was not started" >&2; failures=1; fi

  setup "$good_options" "$good_rules" "$good_config" running
  if run_gate && [ ! -s "$work/calls" ]; then echo "ok: a running container is left alone"; else echo "FAIL: a running container was started again" >&2; failures=1; fi

  refuse() {
    label="$1"; setup "$2" "$3" "$4"
    if run_gate; then echo "FAIL: $label passed the gate" >&2; failures=1
    elif [ -s "$work/calls" ]; then echo "FAIL: $label started the container" >&2; failures=1
    else echo "ok: $label stops the play before the start"; fi
  }
  refuse "missing cache-ingress group" "$good_options" '[{"type": "group", "action": "guest-egress", "enable": 1}]' "$good_config"
  refuse "wrong group name" "$good_options" '[{"type": "group", "action": "guest-egress", "enable": 1}, {"type": "group", "action": "cache-ingres", "enable": 1}]' "$good_config"
  refuse "extra enabled rule" "$good_options" '[{"type": "group", "action": "guest-egress", "enable": 1}, {"type": "group", "action": "cache-ingress", "enable": 1}, {"type": "in", "action": "ACCEPT", "enable": 1}]' "$good_config"
  refuse "disabled group rule" "$good_options" '[{"type": "group", "action": "guest-egress", "enable": 1}, {"type": "group", "action": "cache-ingress", "enable": 0}]' "$good_config"
  refuse "firewall enable 0" '{"enable": 0, "policy_in": "DROP", "policy_out": "DROP", "ipfilter": 1}' "$good_rules" "$good_config"
  refuse "policy_out ACCEPT" '{"enable": 1, "policy_in": "DROP", "ipfilter": 1}' "$good_rules" "$good_config"
  refuse "ipfilter off" '{"enable": 1, "policy_in": "DROP", "policy_out": "DROP"}' "$good_rules" "$good_config"
  refuse "NIC without the firewall flag" "$good_options" "$good_rules" '{"net0": "name=eth0,bridge=cache,gw=10.99.17.1,ip=10.99.17.10/24,type=veth"}'
  refuse "NIC on another vnet" "$good_options" "$good_rules" '{"net0": "name=eth0,bridge=guests,firewall=1,ip=10.99.17.10/24,type=veth"}'
  return "$failures"
}

check_all || { echo "FAIL: the gate does not meet its contract" >&2; exit 1; }

copy="$work/mutant.yml"
sed "/\['cache-ingress', 'guest-egress'\]/d" "$gate" > "$copy"
if cmp -s "$gate" "$copy"; then echo "FAIL: the mutation changed nothing" >&2; exit 1; fi
gate="$copy"
cat > "$work/play.yml" <<EOF
---
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    cache_vmid: 9050
    cache_node: pve01
    cache_vnet: cache
  tasks:
    - ansible.builtin.include_tasks: "$gate"
EOF
if check_all > "$work/mut.log" 2>&1; then
  echo "FAIL: the mutation that drops the group check was not caught" >&2
  exit 1
fi
echo "ok: mutation that drops the group check is rejected: $(grep -m1 FAIL "$work/mut.log")"
