#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${PVE_FIREWALL_ROLE_DIR:-$repo/iac/ansible/roles/pve_firewall}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible >/dev/null || { echo "ERROR: ansible is not installed" >&2; exit 2; }
[ -f "$role/templates/cluster.fw.j2" ] || { echo "ERROR: no cluster.fw.j2 under $role" >&2; exit 2; }

python3 -I - "$repo" "$work" <<'PY'
import json
import sys

import yaml

repo, work = sys.argv[1:3]
host = yaml.safe_load(open(f"{repo}/iac/inventory/hosts.yml", encoding="utf-8"))["all"]["children"]["pve_hosts"]["hosts"]["pve01"]
base = {
    "management_source": host["management_source"],
    "guest_network": host["guest_network"],
    "cache_network": host["cache_network"],
    "cache_endpoint": host["cache_endpoint"],
}
json.dump(base, open(f"{work}/vars-base.json", "w"))
json.dump({**base, "sim_cache_endpoint": host["sim_cache_endpoint"], "sim_cache_sources": host["sim_cache_sources"]}, open(f"{work}/vars-sim.json", "w"))
PY

cat > "$work/check.py" <<'PY'
import ipaddress
import sys

import yaml

repo, base_path, sim_path = sys.argv[1:4]
IPSET = "sim-runners"
errors = []


def parse(path):
    parsed, current = {}, None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip().lower()
            parsed.setdefault(current, [])
            continue
        parsed[current].append(line)
    return parsed


base, sim = parse(base_path), parse(sim_path)
hosts = yaml.safe_load(open(f"{repo}/iac/inventory/hosts.yml", encoding="utf-8"))["all"]["children"]["pve_hosts"]["hosts"]["pve01"]
guest_net = ipaddress.ip_network(hosts["guest_network"]["cidr"])
cache_net = ipaddress.ip_network(hosts["cache_network"]["cidr"])
cache_port = str(hosts["cache_endpoint"]["port"])
sim_address = hosts["sim_cache_endpoint"]["address"]

added_sections = set(sim) - set(base)
if added_sections != {"ipset " + IPSET}:
    errors.append("the sim endpoint must add exactly the section 'ipset %s', it adds %r" % (IPSET, sorted(added_sections)))
for name in base:
    if name != "group guest-egress" and base[name] != sim.get(name):
        errors.append("section [%s] changed: a sim endpoint may only add its ipset and one guest-egress line" % name)

egress_base, egress_sim = base.get("group guest-egress", []), sim.get("group guest-egress", [])
added = [line for line in egress_sim if line not in egress_base]
removed = [line for line in egress_base if line not in egress_sim]
if removed:
    errors.append("guest-egress lost %r" % removed)
if len(added) != 1:
    errors.append("guest-egress must gain exactly one line, it gains %d: %r" % (len(added), added))
elif [line for line in egress_sim if line != added[0]] != egress_base:
    errors.append("the existing guest-egress lines changed order or content")
else:
    tokens = added[0].split()
    options = dict(zip(tokens[2::2], tokens[3::2])) if len(tokens) % 2 == 0 else {}
    if tokens[:2] != ["OUT", "ACCEPT"] or set(options) != {"-source", "-dest", "-p", "-dport"}:
        errors.append("the added line must be 'OUT ACCEPT' with exactly -source, -dest, -p and -dport: %r" % added[0])
    else:
        if options["-source"] != "+dc/" + IPSET:
            errors.append("the source must be the runner ipset +dc/%s, it is %r" % (IPSET, options["-source"]))
        if options["-dest"] != sim_address:
            errors.append("the destination must be the single host %s, it is %r" % (sim_address, options["-dest"]))
        if options["-p"] != "tcp" or options["-dport"] != cache_port:
            errors.append("the rule must be tcp to the single port %s, it is %s %r" % (cache_port, options["-p"], options["-dport"]))
    drops = [i for i, line in enumerate(egress_sim) if line.startswith("OUT DROP")]
    if drops and egress_sim.index(added[0]) > min(drops):
        errors.append("the sim accept must precede every DROP in guest-egress")

members = sim.get("ipset " + IPSET, [])
trial = hosts["sim_cache_sources"]
if not members or members != sorted(set(members)):
    errors.append("the runner ipset must be a sorted, duplicate-free, non-empty list: %r" % members)
for member in members:
    try:
        address = ipaddress.ip_address(member)
    except ValueError:
        errors.append("the runner ipset holds %r, which is not one host address" % member)
        continue
    if address not in guest_net or address == ipaddress.ip_address(hosts["guest_network"]["gateway"]):
        errors.append("runner ipset member %s is not a guest on the guests subnet" % member)
if ipaddress.ip_address(sim_address) not in cache_net or sim_address in (hosts["cache_endpoint"]["address"], hosts["cache_network"]["gateway"]):
    errors.append("the sim address must be a free host address on the cache subnet")

guests = yaml.safe_load(open(f"{repo}/iac/tofu/stacks/guest/guests.yml", encoding="utf-8"))["guests"]["pve01"]
expected = sorted(str(guest_net.network_address + 100 + int(g["slot"])) for g in guests.values() if str(g["flavor"]).startswith("lab/trial-"))
if sorted(members) != expected or sorted(trial) != expected:
    errors.append("the runner ipset %r must be exactly the trial guests of guests.yml %r" % (members, expected))

cache_accept = "OUT ACCEPT -dest %s -p tcp -dport %s" % (hosts["cache_endpoint"]["address"], cache_port)
expected_ingress = [
    "IN ACCEPT -source %s -p tcp -dport %s" % (guest_net, cache_port),
    "IN ACCEPT -source %s -p tcp -dport 22" % hosts["cache_network"]["gateway"],
]
if sim.get("group cache-ingress") != expected_ingress:
    errors.append("cache-ingress must stay %r, the sim cache rides the existing ingress path: %r" % (expected_ingress, sim.get("group cache-ingress")))
if len(egress_base) != 3 or egress_base[0] != cache_accept:
    errors.append("without a sim endpoint guest-egress must be the cache accept, the host-routed drop and the public accept: %r" % egress_base)
for name, lines in sim.items():
    if name not in ("group guest-egress", "ipset " + IPSET) and any(sim_address in line or IPSET in line for line in lines):
        errors.append("section [%s] mentions the sim endpoint or runner set" % name)

if any(IPSET in line for section in base.values() for line in section) or "ipset " + IPSET in base:
    errors.append("a host with no sim endpoint must render no sim ipset and no sim rule")

if errors:
    print("\n".join(errors))
    sys.exit(1)
PY

render() {
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
    ansible localhost -c local -m ansible.builtin.template \
      -a "src=$1/templates/cluster.fw.j2 dest=$work/$3" \
      -e "@$1/defaults/main.yml" -e "@$work/$2" > "$work/ansible.log" 2>&1 \
    || { cat "$work/ansible.log" >&2; echo "FAIL: the template did not render" >&2; return 2; }
}

verify() {
  render "$1" vars-base.json base.fw && render "$1" vars-sim.json sim.fw || return 2
  python3 -I "$work/check.py" "$repo" "$work/base.fw" "$work/sim.fw"
}

verify "$role" || { echo "FAIL: the firewall template does not meet the sim cache path contract" >&2; exit 1; }
echo "ok: one source-limited accept to one host and port, the runner ipset equals the trial guests, nothing else changed"

mutate() {
  local label="$1" file="$2" expr="$3" copy="$work/mut"
  rm -rf "$copy"
  cp -r "$role" "$copy"
  sed -i -e "$expr" "$copy/$file"
  if cmp -s "$role/$file" "$copy/$file"; then
    echo "FAIL: mutation '$label' changed nothing" >&2
    exit 1
  fi
  if verify "$copy" > "$work/mut.log" 2>&1; then
    echo "FAIL: mutation '$label' was not caught" >&2
    exit 1
  fi
  echo "ok: mutation '$label' is rejected: $(head -n1 "$work/mut.log")"
}

sim_rule='^OUT ACCEPT -source +dc\/{{ pve_firewall_sim_cache_ipset }}'
nl=$'\n'
mutate "any source reaches the sim cache" templates/cluster.fw.j2 "s/${sim_rule} -dest/OUT ACCEPT -dest/"
mutate "any port on the sim host" templates/cluster.fw.j2 "s/\(${sim_rule}.*\) -dport {{ pve_firewall_cache_endpoint.port }}/\1/"
mutate "the whole cache subnet as destination" templates/cluster.fw.j2 "s/-dest {{ pve_firewall_sim_cache_endpoint.address }}/-dest {{ pve_firewall_cache_network.cidr }}/"
mutate "a second accepted port" templates/cluster.fw.j2 "/${sim_rule}/a OUT ACCEPT -source +dc/{{ pve_firewall_sim_cache_ipset }} -dest {{ pve_firewall_sim_cache_endpoint.address }} -p tcp -dport 9000"
mutate "a second accepted destination" templates/cluster.fw.j2 "/${sim_rule}/a OUT ACCEPT -source +dc/{{ pve_firewall_sim_cache_ipset }} -dest {{ pve_firewall_cache_endpoint.address }} -p tcp -dport {{ pve_firewall_cache_endpoint.port }}"
mutate "the whole guests subnet in the runner set" templates/cluster.fw.j2 "/\[IPSET {{ pve_firewall_sim_cache_ipset }}\]/a {{ pve_firewall_guest_cidr }}"
mutate "a wider ingress path" templates/cluster.fw.j2 "/^IN ACCEPT -source {{ pve_firewall_cache_network.gateway }} -p tcp -dport 22/a IN ACCEPT -source {{ pve_firewall_guest_cidr }} -p tcp -dport 9000"
mutate "the sim rule after the drop" templates/cluster.fw.j2 "/${sim_rule}/d${nl}/^OUT DROP -dest/a {% if pve_firewall_sim_cache_endpoint.address is defined %}${nl}/^OUT DROP -dest/a OUT ACCEPT -source +dc/{{ pve_firewall_sim_cache_ipset }} -dest {{ pve_firewall_sim_cache_endpoint.address }} -p tcp -dport {{ pve_firewall_cache_endpoint.port }}${nl}/^OUT DROP -dest/a {% endif %}"
mutate "the cache gateway in the runner set" templates/cluster.fw.j2 "/\[IPSET {{ pve_firewall_sim_cache_ipset }}\]/a {{ pve_firewall_cache_network.gateway }}"
echo "OK: the sim cache firewall path"
