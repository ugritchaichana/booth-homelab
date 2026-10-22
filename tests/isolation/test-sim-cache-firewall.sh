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
policy="${SIM_CACHE_POLICY_FILE:-$repo/iac/tailnet/sim-cache-policy.json}"
role_defaults="${SIM_CACHE_DEFAULTS_FILE:-$repo/iac/ansible/roles/sim_cache_service/defaults/main.yml}"
cat > "$work/policy.py" <<'PY'
import json
import sys

import yaml

repo, path, defaults_path = sys.argv[1:4]
port = str(yaml.safe_load(open(f"{repo}/iac/inventory/hosts.yml", encoding="utf-8"))["all"]["children"]["pve_hosts"]["hosts"]["pve01"]["cache_endpoint"]["port"])
defaults = yaml.safe_load(open(defaults_path, encoding="utf-8"))
store_ports = sorted({defaults[k] for k in ("sim_cache_service_s3_port", "sim_cache_service_filer_port", "sim_cache_service_master_port", "sim_cache_service_volume_port")})
# every port the store opens, each with its gRPC twin (http port + 10000), plus the ports a shell, a web server or a proxy might add
denied_ports = sorted(set(store_ports) | {p + 10000 for p in store_ports} | {22, 80, 443})
errors = []
try:
    text = open(path, encoding="utf-8").read()
    doc = json.loads(text)
except (OSError, ValueError) as err:
    print("the tailnet policy snippet is unreadable: %s" % err)
    sys.exit(1)

if set(doc) != {"tagOwners", "grants", "tests"}:
    errors.append("the snippet holds %r, expected exactly tagOwners, grants and tests (no acls)" % sorted(doc))
# a wildcard may only appear in a test that denies; every grant, tag owner and accept list stays literal
literal = {k: v for k, v in doc.items() if k != "tests"}
if "*" in json.dumps(literal) or any("*" in str(t.get("accept", [])) for t in doc.get("tests", [])):
    errors.append("the snippet must not contain a wildcard outside a deny test")
if set(doc.get("tagOwners", {})) != {"tag:ci-sim", "tag:lab-cache"}:
    errors.append("tagOwners must name exactly tag:ci-sim and tag:lab-cache")
grants = doc.get("grants", [])
if len(grants) != 1 or grants[0] != {"src": ["tag:ci-sim"], "dst": ["tag:lab-cache"], "ip": ["tcp:" + port]}:
    errors.append("grants must be exactly one: tag:ci-sim to tag:lab-cache on tcp:%s, found %r" % (port, grants))
tests = doc.get("tests", [])


def entry(src):
    found = [t for t in tests if t.get("src") == src]
    return found[0] if found else {}


forward, member, reverse = entry("tag:ci-sim"), entry("autogroup:member"), entry("tag:lab-cache")
if "tag:lab-cache:" + port not in forward.get("accept", []):
    errors.append("a tests entry must assert tag:ci-sim reaches tag:lab-cache:%s" % port)
for number in denied_ports:
    if f"tag:lab-cache:{number}" not in forward.get("deny", []):
        errors.append("the tag:ci-sim test must deny tag:lab-cache:%d" % number)
    if f"tag:lab-cache:{number}" not in member.get("deny", []):
        errors.append("the autogroup:member test must deny tag:lab-cache:%d" % number)
# the hosted runners join with --accept-routes and the full policy may still hold an allow-all: tag:ci-sim must be denied every member
# device (the PVE UI forward on 8006, ssh) and every cache-node port but the cache port, as a range on each side of it
for needle in ("autogroup:member:*", "autogroup:member:22", "autogroup:member:8006", f"tag:lab-cache:1-{int(port) - 1}", f"tag:lab-cache:{int(port) + 1}-65535"):
    if needle not in forward.get("deny", []):
        errors.append("the tag:ci-sim test must deny %s" % needle)
if "tag:lab-cache:" + port not in member.get("deny", []) or "accept" in member:
    errors.append("a tests entry must assert a member identity is denied the cache port tag:lab-cache:%s" % port)
if not reverse.get("deny") or "accept" in reverse:
    errors.append("a tests entry must assert tag:lab-cache may not open any connection")
if errors:
    print("\n".join(errors))
    sys.exit(1)
PY

policy_verify() { python3 -I "$work/policy.py" "$repo" "$1" "${2:-$role_defaults}"; }
policy_verify "$policy" || { echo "FAIL: the tailnet policy snippet does not meet the contract" >&2; exit 1; }
echo "ok: the tailnet snippet grants one tag to one tag on the cache port and asserts the denials"

policy_mutate() {
  local label="$1" expr="$2"
  sed -e "$expr" "$policy" > "$work/policy-mut.json"
  if cmp -s "$policy" "$work/policy-mut.json"; then echo "FAIL: policy mutation '$label' changed nothing" >&2; exit 1; fi
  if policy_verify "$work/policy-mut.json" > "$work/mut.log" 2>&1; then echo "FAIL: policy mutation '$label' was not caught" >&2; exit 1; fi
  echo "ok: policy mutation '$label' is rejected: $(head -n1 "$work/mut.log")"
}
policy_mutate "any source" 's/"src": \["tag:ci-sim"\]/"src": ["*"]/'
policy_mutate "any destination" 's/"dst": \["tag:lab-cache"\]/"dst": ["*"]/'
policy_mutate "a second port" 's/"ip": \["tcp:8080"\]/"ip": ["tcp:8080", "tcp:22"]/'
policy_mutate "every port" 's/"ip": \["tcp:8080"\]/"ip": ["*"]/'
policy_mutate "another port" 's/"ip": \["tcp:8080"\]/"ip": ["tcp:9000"]/'
policy_mutate "a rule with the cache tag as source" 's/^{\r\?$/{\n  "acls": [{"action": "accept", "src": ["tag:lab-cache"], "dst": ["tag:ci-sim:8080"]}],/'
policy_mutate "a member identity granted every port" 's/^  "grants": \[\r\?$/  "grants": [{"src": ["autogroup:member"], "dst": ["tag:lab-cache"], "ip": ["*"]},/'
policy_mutate "a member identity granted every tcp port" 's/^  "grants": \[\r\?$/  "grants": [{"src": ["autogroup:member"], "dst": ["tag:lab-cache"], "ip": ["tcp:*"]},/'
policy_mutate "a member identity granted the cache port" 's/^  "grants": \[\r\?$/  "grants": [{"src": ["autogroup:member"], "dst": ["tag:lab-cache"], "ip": ["tcp:8080"]},/'
policy_mutate "the assertions removed" 's/"tests": \[/"tests-removed": [/'
policy_mutate "the reverse assertion dropped" 's/"src": "tag:lab-cache"/"src": "tag:other"/'
policy_mutate "every member device no longer denied to the hosted runners" 's/"autogroup:member:\*", //'
policy_mutate "the pve ui forward no longer denied to the hosted runners" 's/"autogroup:member:8006", //'
policy_mutate "ssh to a member device no longer denied to the hosted runners" 's/"autogroup:member:22", //'
policy_mutate "the ports below the cache port no longer denied" 's/, "tag:lab-cache:1-8079"//'
policy_mutate "the ports above the cache port no longer denied" 's/, "tag:lab-cache:8081-65535"//'
policy_mutate "a wildcard in an accept list" 's/"accept": \["tag:lab-cache:8080"\]/"accept": ["tag:lab-cache:*"]/'
policy_mutate "the member assertion dropped" 's/"src": "autogroup:member"/"src": "tag:other"/'
policy_mutate "a store grpc port left out" 's/, "tag:lab-cache:18333"//g'
policy_mutate "the filer port left out" 's/, "tag:lab-cache:8888"//g'
policy_mutate "a stale port of the previous store" 's/"tag:lab-cache:9333"/"tag:lab-cache:9001"/g'
sed -e 's/^sim_cache_service_filer_port: 8888/sim_cache_service_filer_port: 8889/' "$role_defaults" > "$work/defaults-mut.yml"
cmp -s "$role_defaults" "$work/defaults-mut.yml" && { echo "FAIL: the defaults mutation changed nothing" >&2; exit 1; }
if policy_verify "$policy" "$work/defaults-mut.yml" > "$work/mut.log" 2>&1; then echo "FAIL: a store port the policy does not list was not caught" >&2; exit 1; fi
echo "ok: a store port the policy does not list is rejected: $(head -n1 "$work/mut.log")"
echo "OK: the sim cache firewall path"
