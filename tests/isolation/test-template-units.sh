#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${PVE_TEMPLATES_ROLE_DIR:-$repo/iac/ansible/roles/pve_templates}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook is not installed" >&2; exit 2; }
for unit in homelab-template-guest@.service homelab-template-build@.service homelab-template-failure@.service; do
  [ -f "$role/files/$unit" ] || { echo "FAIL: $unit is missing under $role/files" >&2; exit 1; }
done

python3 -I - "$repo/iac/inventory/hosts.yml" "$work/vars.json" "$role" <<'PY'
import json, sys, yaml
host = yaml.safe_load(open(sys.argv[1]))["all"]["children"]["pve_hosts"]["hosts"]["pve01"]
json.dump({"guest_network": host["guest_network"], "pve_node_name": "n1", "role_path": sys.argv[3]}, open(sys.argv[2], "w"))
PY

cat > "$work/render.yml" <<YML
---
- name: Render what the role installs for the guest unit and the orchestrator
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - $role/defaults/main.yml
  tasks:
    - name: Render the guest unit drop-in
      ansible.builtin.template:
        src: $role/templates/10-site.conf.j2
        dest: "$work/10-site.conf"
        mode: "0600"

    - name: Render the orchestrator configuration
      ansible.builtin.copy:
        content: "{{ pve_templates_config | to_nice_json }}"
        dest: "$work/config.json"
        mode: "0600"
YML
ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
  ansible-playbook "$work/render.yml" -e "@$work/vars.json" > "$work/render.log" 2>&1 \
  || { cat "$work/render.log" >&2; echo "FAIL: the role did not render" >&2; exit 1; }

cat > "$work/check-guest-unit.py" <<'PY'
import re
import sys


def parse(path):
    sections, current = {}, None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            current = sections.setdefault(line.strip("[]"), {})
        else:
            key, _, value = line.partition("=")
            current.setdefault(key, []).append(value)
    return sections


unit, dropin, subnet, user = parse(sys.argv[1]), parse(sys.argv[2]), sys.argv[3], sys.argv[4]
service, extra = unit["Service"], dropin["Service"]
problems = []
users = service.get("User", [])
if users != [user] or users[0] in ("root", "0", ""):
    problems.append("User= is %s, wanted the non-root %s" % (users, user))
if service.get("IPAddressDeny") != ["any"]:
    problems.append("IPAddressDeny=any is missing")
if extra.get("IPAddressAllow") != [subnet] or "IPAddressAllow" in service:
    problems.append("IPAddressAllow is %s, wanted only the guest subnet %s" % (extra.get("IPAddressAllow"), subnet))
for key, value in (("ProtectSystem", "strict"), ("ProtectHome", "yes"), ("NoNewPrivileges", "yes"), ("PrivateTmp", "yes"), ("CapabilityBoundingSet", "")):
    if service.get(key) != [value]:
        problems.append("%s=%s is missing" % (key, value))
inaccessible = " ".join(service.get("InaccessiblePaths", [])).split()
for path in ("/etc/pve", "/root"):
    if path not in inaccessible:
        problems.append("InaccessiblePaths does not hold %s" % path)
if not any(re.fullmatch(r"/usr/local/libexec/homelab-template/guest-step cleanup", v) for v in service.get("ExecStopPost", [])):
    problems.append("ExecStopPost= does not remove the key and known_hosts")
if "Environment" not in service or not any(v.startswith("HOME=/run/") for v in service["Environment"]):
    problems.append("HOME is not pointed at the runtime directory")
if problems:
    print("; ".join(problems))
    sys.exit(1)
PY

failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$3', wanted '$2'"; failures=$((failures + 1)); fi
}
subnet="$(python3 -I -c "import json; print(json.load(open('$work/vars.json'))['guest_network']['cidr'])")"
unit="${GUEST_UNIT:-$role/files/homelab-template-guest@.service}"
checker() { python3 -I "$work/check-guest-unit.py" "$1" "$2" "$subnet" homelab-tmpl > "$work/check.out" 2>&1 && echo ok || echo bad; }

echo "== the shipped guest unit"
expect "the shipped unit with its rendered drop-in satisfies every sandbox rule" ok "$(checker "$unit" "$work/10-site.conf")"
expect "the unit user is the one the role creates" "homelab-tmpl" "$(python3 -I -c "import yaml; print(yaml.safe_load(open('$role/defaults/main.yml'))['pve_templates_guest_user'])")"
expect "the unit starts the script the role installs" "1" "$(grep -c '^ExecStart=/usr/local/libexec/homelab-template/guest-step %i$' "$unit")"
expect "the role installs the script at that path" "1" "$(grep -c 'pve_templates_libexec_dir: /usr/local/libexec/homelab-template$' "$role/defaults/main.yml")"

echo "== the checker is not vacuous: each mutation of the unit fails it"
mutate() {
  sed "$2" "$unit" > "$work/mutant.service"
  expect "$1" bad "$(checker "$work/mutant.service" "$work/10-site.conf")"
}
mutate "a unit without IPAddressDeny=any fails" '/^IPAddressDeny=any$/d'
mutate "a unit running as root fails" 's/^User=homelab-tmpl$/User=root/'
mutate "a unit without a User= fails" '/^User=/d'
mutate "a unit without NoNewPrivileges fails" '/^NoNewPrivileges=yes$/d'
mutate "a unit without ProtectSystem=strict fails" 's/^ProtectSystem=strict$/ProtectSystem=full/'
mutate "a unit without ProtectHome=yes fails" '/^ProtectHome=yes$/d'
mutate "a unit that can see /etc/pve fails" 's#^InaccessiblePaths=/etc/pve /root$#InaccessiblePaths=/root#'
mutate "a unit that can see /root fails" 's#^InaccessiblePaths=/etc/pve /root$#InaccessiblePaths=/etc/pve#'
mutate "a unit without the key cleanup fails" '/^ExecStopPost=/d'
mutate "a unit that allows more than the subnet fails" 's/^IPAddressDeny=any$/IPAddressDeny=any\nIPAddressAllow=0.0.0.0\/0/'
printf '[Service]\nIPAddressAllow=0.0.0.0/0\n' > "$work/wide.conf"
expect "a drop-in that allows every address fails" bad "$(checker "$unit" "$work/wide.conf")"
printf '[Service]\nIPAddressAllow=%s\nIPAddressAllow=10.0.0.0/8\n' "$subnet" > "$work/two.conf"
expect "a drop-in that adds a second allowed range fails" bad "$(checker "$unit" "$work/two.conf")"

echo "== the other units"
build="$role/files/homelab-template-build@.service"
expect "the build unit runs as root through the orchestrator" "1" "$(grep -c '^ExecStart=/usr/local/sbin/homelab-template build %i$' "$build")"
expect "the build unit names the failure unit in OnFailure=" "1" "$(grep -c '^OnFailure=homelab-template-failure@%i.service$' "$build")"
expect "the failure unit records the failure through the orchestrator" "1" "$(grep -c '^ExecStart=/usr/local/sbin/homelab-template record-failure %i$' "$role/files/homelab-template-failure@.service")"
expect "no timer ships with the framework" "0" "$(find "$role" -name '*.timer' | wc -l | tr -d ' ')"
expect "the role does not enable or start any unit" "0" "$(grep -cE 'enabled:|state: (started|restarted)' "$role/tasks/main.yml")"

echo "== the rendered orchestrator configuration carries the policy file, not a copy"
python3 -I - "$work/config.json" "$repo/iac/policy/runner-class.yml" "$work/vars.json" > "$work/config-check.out" 2>&1 <<'PY' && echo ok > "$work/config-check.rc" || echo bad > "$work/config-check.rc"
import json, sys, yaml
cfg, policy, network = json.load(open(sys.argv[1])), yaml.safe_load(open(sys.argv[2])), json.load(open(sys.argv[3]))["guest_network"]
assert cfg["fw_options"] == policy["runner_class_firewall_options"], "firewall options differ from runner-class.yml"
assert cfg["group"] == policy["runner_class_security_group"], "security group differs from runner-class.yml"
assert cfg["nic_firewall"] == policy["runner_class_nic_firewall"], "NIC firewall differs from runner-class.yml"
assert (cfg["vnet"], cfg["cidr"], cfg["gateway"]) == (network["vnet"], network["cidr"], network["gateway"]), "guest network differs from the inventory"
assert cfg["require_root"] is True, "require_root must default to true"
assert cfg["pool"] == "templates", "templates pool differs from ADR 0036"
bases = sorted(c["vmid_base"] for c in cfg["classes"].values())
assert all(not (b <= v < b + 100) for b in bases for v in (9101, 9102)), "a class block holds a probe VMID"
assert all(c["verify_hook"] == "" for c in cfg["classes"].values()), "no class hook is configured yet"
PY
expect "the configuration follows runner-class.yml, the inventory and the pool decision" ok "$(cat "$work/config-check.rc")"
[ "$(cat "$work/config-check.rc")" = ok ] || cat "$work/config-check.out"

[ "$failures" -eq 0 ] || { echo "FAILED: $failures check(s)"; exit 1; }
echo "OK: template units"
