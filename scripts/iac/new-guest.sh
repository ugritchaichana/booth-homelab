#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guests_file="${HOMELAB_GUESTS_FILE:-$repo/iac/tofu/stacks/guest/guests.yml}"
tofu_sh="${HOMELAB_TOFU_SH:-$repo/scripts/iac/tofu.sh}"
inventory="${HOMELAB_INVENTORY:-$repo/iac/inventory/hosts.yml}"
catalog="$repo/iac/tofu/flavors.json"
classes="$repo/iac/ansible/roles/pve_templates/defaults/main.yml"
role_re='^[a-z][a-z0-9-]{0,62}$'
version_re='^v[1-9][0-9]*$'

die() { echo "ERROR: $*" >&2; exit 1; }
usage() {
  cat >&2 << 'USAGE'
usage: new-guest.sh --flavor PROVIDER/INSTANCE --template CLASS [--role ROLE] [--version vN] [--host HOST] [--apply]
  Adds or updates the guest ROLE in the guest list, then plans (or applies) the guest stack.
  ROLE defaults to guest-NN; the Proxmox name is ROLE-CLASS-vN. Without --version the guest follows the current template.
USAGE
  exit 2
}
need() { command -v "$1" > /dev/null || die "$1 is not installed (scripts/bootstrap/operator-toolchain.sh)"; }

flavor="" template="" role="" version="" host="" apply=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --flavor | --template | --role | --name | --version | --host)
      [ "$#" -ge 2 ] || usage
      case "$1" in
        --flavor) flavor="$2" ;;
        --template) template="$2" ;;
        --role | --name) role="$2" ;;
        --version) version="$2" ;;
        --host) host="$2" ;;
      esac
      shift 2
      ;;
    --apply) apply=1; shift ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done
[ -n "$flavor" ] && [ -n "$template" ] || usage

[ -z "$role" ] || [[ "$role" =~ $role_re ]] || die "role $role must be lowercase letters, digits and hyphens, starting with a letter, at most 63 characters"
[ -z "$version" ] || [[ "$version" =~ $version_re ]] || die "version $version must look like v4"

need python3

edit_guests() {
  python3 - "$guests_file" "$catalog" "$classes" "$inventory" "$host" "$flavor" "$template" "$role" "$version" << 'PY'
import json, os, sys, tempfile, yaml

path, catalog, classes, inventory, host, flavor, template, role, version = sys.argv[1:10]


def fail(message):
    print("ERROR: " + message, file=sys.stderr)
    sys.exit(1)


provider, _, instance = flavor.partition("/")
known = json.load(open(catalog))["providers"].get(provider, {}).get("instances", {})
if instance not in known:
    fail(f"flavor {flavor} is not in iac/tofu/flavors.json")

known_classes = yaml.safe_load(open(classes))["pve_templates_classes"]
if template not in known_classes:
    fail(f"template {template} is not one of: {' '.join(known_classes)}")

hosts = yaml.safe_load(open(inventory))["all"]["children"]["pve_hosts"]["hosts"]
if not host:
    if len(hosts) != 1:
        fail("several hosts in the inventory; pass --host: " + " ".join(hosts))
    host = next(iter(hosts))
if host not in hosts:
    fail(f"host {host} is not a pve_hosts entry in iac/inventory/hosts.yml")

data = yaml.safe_load(open(path)) or {}
section = data.setdefault("guests", {}).setdefault(host, {})
taken = {entry["slot"] for entry in section.values()}
existing = section.get(role) if role else None
if existing:
    slot = existing["slot"]
else:
    free = [n for n in range(1, 100) if n not in taken]
    if not free:
        fail(f"no free slot on {host}: slots 1 to 99 are all used")
    slot = free[0]
    role = role or f"guest-{slot:02d}"
if len(role) + len(template) + 3 > 63:
    fail(f"role {role} makes the name {role}-{template}-vN longer than 63 characters")

entry = {"flavor": flavor, "template_class": template}
if version:
    entry["template_version"] = int(version[1:])
entry["slot"] = slot
section[role] = entry

directory = os.path.dirname(os.path.abspath(path))
handle, temp = tempfile.mkstemp(dir=directory, prefix=".guests.")
with os.fdopen(handle, "w") as out:
    yaml.safe_dump(data, out, explicit_start=True, sort_keys=False, default_flow_style=False)
os.replace(temp, path)
print(f"{host} {role} {slot}")
PY
}

result="$(edit_guests)"
read -r host role slot <<< "$result"
echo "guest $role on $host: $flavor, $template${version:+ $version}, slot $slot"

extra=()
[ -z "${HOMELAB_GUESTS_FILE:-}" ] || extra=("-var=guests_file=$guests_file")
verb=plan
[ "$apply" -eq 0 ] || verb=apply
bash "$tofu_sh" guest "$host" init -input=false
bash "$tofu_sh" guest "$host" "$verb" ${extra[@]+"${extra[@]}"}
