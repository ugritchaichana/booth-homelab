#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="${GUARD_SCRIPT:-$repo/iac/ansible/roles/pve_firewall/files/guest-firewall-guard.py}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state"

cat > "$work/bin/pvesh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
world = json.load(open(os.environ["FAKE_WORLD"]))
path = sys.argv[2]
if world.get("list_fail") and path == "/cluster/resources":
    sys.exit(2)
if path == "/cluster/resources":
    print(json.dumps(world["resources"]))
    sys.exit(0)
parts = path.strip("/").split("/")
vmid, kind = parts[3], "/".join(parts[4:])
if kind in world.get("fail", {}).get(vmid, []):
    sys.exit(2)
table = {"config": "config", "firewall/options": "options", "firewall/rules": "rules"}
print(json.dumps(world[table[kind]][vmid]))
PY
for tool in qm pct; do
  cat > "$work/bin/$tool" <<SH
#!/bin/sh
echo "$tool \$*" >> "$work/calls"
SH
done
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" FAKE_WORLD="$work/world.json"

good_nic="virtio=AA:BB:CC:DD:EE:01,bridge=guests,firewall=1"
good_opts='{"enable": 1, "policy_in": "DROP", "policy_out": "DROP", "ipfilter": 1}'
good_rules='[{"type": "group", "action": "guest-egress", "enable": 1}]'
gateway="10.99.16.1"
group_rule='{"type": "group", "action": "guest-egress", "enable": 1, "pos": 0}'

cat > "$work/world.json" <<JSON
{
  "resources": [
    {"vmid": 9101, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9102, "type": "lxc", "node": "n1", "status": "running"},
    {"vmid": 9103, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9104, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9105, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9106, "type": "qemu", "node": "n1", "status": "stopped"},
    {"vmid": 9107, "type": "lxc", "node": "n1", "status": "running"},
    {"vmid": 9108, "type": "qemu", "node": "n2", "status": "running"},
    {"vmid": 9109, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9110, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9111, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9112, "type": "qemu", "node": "n1", "status": "running"},
    {"vmid": 9113, "type": "qemu", "node": "n1", "status": "running"}
  ],
  "config": {
    "9101": {"net0": "$good_nic"},
    "9102": {"net0": "name=eth0,bridge=guests,firewall=1,type=veth"},
    "9103": {"net0": "$good_nic"},
    "9104": {"net0": "$good_nic", "net1": "virtio=AA:BB:CC:DD:EE:02,bridge=guests,firewall=0"},
    "9105": {"net0": "virtio=AA:BB:CC:DD:EE:03,bridge=vmbr9,firewall=0"},
    "9106": {"net0": "$good_nic"},
    "9107": {"net0": "name=eth0,bridge=guests,firewall=1,type=veth"},
    "9108": {"net0": "$good_nic"},
    "9109": {"net0": "$good_nic"},
    "9110": {"net0": "$good_nic"},
    "9111": {"net0": "$good_nic"},
    "9112": {"net0": "$good_nic"},
    "9113": {"net0": "$good_nic"}
  },
  "options": {
    "9101": $good_opts,
    "9102": {"enable": 1, "policy_in": "DROP", "policy_out": "ACCEPT", "ipfilter": 1},
    "9103": $good_opts,
    "9104": $good_opts,
    "9105": {"enable": 0},
    "9106": {"enable": 1, "policy_out": "DROP"},
    "9107": $good_opts,
    "9108": {"enable": 0},
    "9109": $good_opts,
    "9110": $good_opts,
    "9111": $good_opts,
    "9112": $good_opts,
    "9113": $good_opts
  },
  "rules": {
    "9101": $good_rules,
    "9102": $good_rules,
    "9103": [{"type": "group", "action": "guest-egress", "enable": 0}],
    "9104": $good_rules,
    "9105": [{"type": "out", "action": "ACCEPT", "enable": 1, "pos": 0}],
    "9106": $good_rules,
    "9107": $good_rules,
    "9108": [],
    "9109": [$group_rule, {"type": "out", "action": "ACCEPT", "enable": 1, "pos": 1}],
    "9110": [$group_rule, {"type": "in", "action": "ACCEPT", "enable": 1, "pos": 1}],
    "9111": [$group_rule, {"type": "in", "action": "ACCEPT", "proto": "tcp", "dport": "22", "source": "$gateway", "enable": 1, "pos": 1}],
    "9112": [$group_rule, {"type": "out", "action": "ACCEPT", "enable": 0, "pos": 1}],
    "9113": [$group_rule, {"type": "in", "action": "ACCEPT", "proto": "tcp", "dport": "22", "source": "10.99.16.9", "enable": 1, "pos": 1}]
  },
  "fail": {"9107": ["firewall/rules"]}
}
JSON

guard_run() { python3 -I "$guard" --node n1 --vnet guests --group guest-egress --gateway "$gateway" --state-dir "$work/state" "$@"; }
failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$3', wanted '$2'"; failures=$((failures + 1)); fi
}
calls() { if [ -f "$work/calls" ]; then sort "$work/calls" | tr '\n' ';'; fi; }

set +e
guard_run > "$work/run1.log" 2>&1; rc=$?
set -e
expect "run 1 exits 4 because one guest could not be read" 4 "$rc"
expect "run 1 stops exactly the guests that violate" "pct stop 9102;qm stop 9103;qm stop 9104;qm stop 9109;qm stop 9110;qm stop 9113;" "$(calls)"
expect "compliant guest 9101 is left alone" 0 "$(grep -c 9101 "$work/calls" || true)"
expect "guest off the guests vnet is left alone" 0 "$(grep -c 9105 "$work/calls" || true)"
expect "stopped violator 9106 is not touched" 0 "$(grep -c 9106 "$work/calls" || true)"
expect "guest of another node is left alone" 0 "$(grep -c 9108 "$work/calls" || true)"
expect "extra OUT ACCEPT rule beside the group stops the guest" 1 "$(grep -c 'qm stop 9109' "$work/calls" || true)"
expect "extra IN ACCEPT rule from anywhere stops the guest" 1 "$(grep -c 'qm stop 9110' "$work/calls" || true)"
expect "inbound tcp/22 from another source stops the guest" 1 "$(grep -c 'qm stop 9113' "$work/calls" || true)"
expect "inbound tcp/22 from the gateway is left alone" 0 "$(grep -c 9111 "$work/calls" || true)"
expect "a disabled extra rule is left alone" 0 "$(grep -c 9112 "$work/calls" || true)"
expect "violation markers exist for the guests that violate" "9102 9103 9104 9106 9109 9110 9113" "$(ls "$work/state/violations" | tr '\n' ' ' | sed 's/ $//')"
expect "no marker for the compliant guest" 0 "$(ls "$work/state/violations" | grep -c 9101 || true)"
expect "unreadable guest 9107 is not stopped on the first run" 0 "$(grep -c 9107 "$work/calls" || true)"
expect "no command ever starts anything" 0 "$(grep -c -E ' start ' "$work/calls" || true)"
grep -q 'policy_out is not DROP' "$work/run1.log" && echo "PASS journal line names the reason" || { echo "FAIL journal line names the reason"; failures=$((failures + 1)); }
grep -q 'vmid=9109 .*enabled rule outside the allowed set (pos 1)' "$work/run1.log" && echo "PASS journal line names the extra rule" || { echo "FAIL journal line names the extra rule"; failures=$((failures + 1)); }

: > "$work/calls"
set +e
guard_run > /dev/null 2>&1; guard_run > /dev/null 2>&1; rc=$?
set -e
expect "unreadable guest is stopped on the third consecutive run" "pct stop 9107;" "$(grep 9107 "$work/calls" | sort -u | tr '\n' ';')"

: > "$work/calls"
python3 - "$work/world.json" <<'PY'
import json, sys
p = sys.argv[1]
w = json.load(open(p))
w["list_fail"] = True
json.dump(w, open(p, "w"))
PY
set +e
guard_run > "$work/run3.log" 2>&1; rc=$?
set -e
expect "a failing guest list stops nothing" 0 "$(wc -l < "$work/calls" | tr -d ' ')"
expect "a failing guest list exits 4" 4 "$rc"

python3 - "$work/world.json" <<'PY'
import json, sys
p = sys.argv[1]
w = json.load(open(p))
w["list_fail"] = False
w["fail"] = {}
good_opts = {"enable": 1, "policy_in": "DROP", "policy_out": "DROP", "ipfilter": 1}
good_rules = [{"type": "group", "action": "guest-egress", "enable": 1}]
for vmid in ("9102", "9103", "9104", "9106", "9107", "9109", "9110", "9113"):
    w["options"][vmid] = good_opts
    w["rules"][vmid] = good_rules
    w["config"][vmid] = {"net0": "virtio=AA:BB:CC:DD:EE:09,bridge=guests,firewall=1"}
json.dump(w, open(p, "w"))
PY
: > "$work/calls"
set +e
guard_run > "$work/run4.log" 2>&1; rc=$?
set -e
expect "all guests fixed: exit 0" 0 "$rc"
expect "all guests fixed: nothing stopped" 0 "$(wc -l < "$work/calls" | tr -d ' ')"
expect "markers clear once the guests comply" 0 "$(ls "$work/state/violations" | wc -l | tr -d ' ')"

[ "$failures" -eq 0 ] || { echo "FAILED: $failures check(s)"; exit 1; }
echo "OK: guest firewall guard"
