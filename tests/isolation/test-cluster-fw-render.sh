#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${PVE_FIREWALL_ROLE_DIR:-$repo/iac/ansible/roles/pve_firewall}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible >/dev/null || { echo "ERROR: ansible is not installed" >&2; exit 2; }
[ -f "$role/templates/cluster.fw.j2" ] || { echo "ERROR: no cluster.fw.j2 under $role" >&2; exit 2; }

cat > "$work/vars.json" <<'JSON'
{"management_source": "10.99.0.1", "pve_firewall_host_routed_prefixes": ["198.51.100.0/24", "203.0.113.0/24"]}
JSON

ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
  ansible localhost -c local -m ansible.builtin.template \
    -a "src=$role/templates/cluster.fw.j2 dest=$work/cluster.fw" \
    -e "@$role/defaults/main.yml" -e "@$work/vars.json" > "$work/ansible.log" 2>&1 \
  || { cat "$work/ansible.log" >&2; echo "FAIL: the template did not render" >&2; exit 1; }

python3 -I - "$work/cluster.fw" <<'PY'
import ipaddress
import sys

# Special-purpose IPv4 blocks a guest must never reach, taken from the IANA IPv4 Special-Purpose
# Address Registry (RFC 6890) and the RFCs behind its entries, not from the role.
RFC_DENY = [
    ("0.0.0.0/8", "RFC 1122 section 3.2.1.3, this network"),
    ("10.0.0.0/8", "RFC 1918, private use"),
    ("100.64.0.0/10", "RFC 6598, shared address space"),
    ("127.0.0.0/8", "RFC 1122 section 3.2.1.3, loopback"),
    ("169.254.0.0/16", "RFC 3927, link local"),
    ("172.16.0.0/12", "RFC 1918, private use"),
    ("192.0.0.0/24", "RFC 6890, IETF protocol assignments"),
    ("192.0.2.0/24", "RFC 5737, documentation TEST-NET-1"),
    ("192.168.0.0/16", "RFC 1918, private use"),
    ("198.18.0.0/15", "RFC 2544, benchmarking"),
    ("198.51.100.0/24", "RFC 5737, documentation TEST-NET-2"),
    ("203.0.113.0/24", "RFC 5737, documentation TEST-NET-3"),
    ("224.0.0.0/4", "RFC 5771, multicast"),
    ("240.0.0.0/4", "RFC 1112 section 4, reserved"),
]
PUBLIC_SAMPLES = [
    "1.1.1.1", "8.8.8.8", "9.9.9.9", "93.184.216.34", "9.255.255.255", "11.0.0.0",
    "99.255.255.255", "100.63.255.255", "100.128.0.0", "126.255.255.255", "128.0.0.1",
    "169.253.255.255", "169.255.0.0", "172.15.255.255", "172.32.0.0", "192.0.1.1", "192.0.3.0",
    "192.167.255.255", "192.169.0.0", "198.17.255.255", "198.20.0.0", "198.51.99.255",
    "198.51.101.0", "203.0.112.255", "203.0.114.0", "223.255.255.254",
]
MANAGEMENT = {"10.99.0.1"}
HOST_ROUTED = {"198.51.100.0/24", "203.0.113.0/24"}

sections = {}
current = None
for raw in open(sys.argv[1], encoding="utf-8"):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("[") and line.endswith("]"):
        current = line[1:-1].strip().lower()
        sections.setdefault(current, [])
        continue
    sections[current].append(line)

errors = []

def fail(message):
    errors.append(message)

def entries(name):
    out = []
    for line in sections.get("ipset " + name, []):
        nomatch = line.startswith("!")
        out.append((ipaddress.ip_network(line.lstrip("!"), strict=True), nomatch))
    return out

for name, lines in sections.items():
    if name.startswith("ipset "):
        for line in lines:
            if ipaddress.ip_network(line.lstrip("!"), strict=True).prefixlen == 0:
                fail("ipset %s holds a zero-prefix entry %s, which the Proxmox firewall rejects" % (name, line))

def in_set(address, members):
    ip = ipaddress.ip_address(address)
    covering = [(net.prefixlen, nomatch) for net, nomatch in members if ip in net]
    return bool(covering) and not max(covering)[1]

public = entries("public-v4")
if not public:
    fail("ipset public-v4 is missing")

for prefix, why in RFC_DENY:
    net = ipaddress.ip_network(prefix)
    probes = {net.network_address, net.broadcast_address, net.network_address + net.num_addresses // 2}
    leaked = sorted(str(p) for p in probes if in_set(str(p), public))
    if leaked:
        fail("MISSING deny prefix %s (%s): %s would be accepted for guest egress" % (prefix, why, ", ".join(leaked)))

for address in PUBLIC_SAMPLES:
    if not in_set(address, public):
        fail("public address %s is not accepted for guest egress" % address)

rules = sections.get("group guest-egress")
expected_rules = ["OUT DROP -dest +dc/host-routed -log info", "OUT ACCEPT -dest +dc/public-v4"]
if rules is None:
    fail("security group guest-egress is missing")
elif rules != expected_rules:
    fail("guest-egress rules are %r, expected %r in this order" % (rules, expected_rules))

if {str(net) for net, _ in entries("host-routed")} != HOST_ROUTED:
    fail("ipset host-routed does not hold the configured prefixes")
if {str(net.network_address) for net, _ in entries("management")} != MANAGEMENT:
    fail("ipset management is not exactly the management source")
if sections.get("aliases") != ["local_network " + next(iter(MANAGEMENT))]:
    fail("local_network is not pinned to the management source, so the node subnet would join management")
options = sections.get("options", [])
if "enable: 1" not in options or "policy_in: DROP" not in options:
    fail("cluster options must enable the firewall with policy_in DROP")

if errors:
    for message in errors:
        print("FAIL: " + message)
    sys.exit(1)
print("OK: %d deny prefixes, %d public samples, group and ipsets as expected" % (len(RFC_DENY), len(PUBLIC_SAMPLES)))
PY
