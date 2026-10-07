#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${CACHE_SERVICE_ROLE_DIR:-$repo/iac/ansible/roles/cache_service}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible >/dev/null || { echo "ERROR: ansible is not installed" >&2; exit 2; }
[ -f "$role/templates/bazel-remote.service.j2" ] || { echo "ERROR: no unit template under $role" >&2; exit 2; }

sentinel="sentinel-writer-password-must-never-reach-the-unit-0123456789"
cat > "$work/vars.json" <<JSON
{"cache_endpoint": {"address": "10.99.17.10", "port": 8080}, "cache_writer_password": "$sentinel"}
JSON

cat > "$work/check.py" <<'PY'
import sys
import yaml

unit_path, tasks_path, defaults_path, sentinel = sys.argv[1:5]
errors = []

text = open(unit_path, encoding="utf-8").read()
lines = [raw.strip() for raw in text.splitlines()]
exec_start = []
for i, line in enumerate(lines):
    if line.startswith("ExecStart="):
        joined = line[len("ExecStart="):]
        while joined.endswith("\\"):
            i += 1
            joined = joined[:-1] + " " + lines[i]
        exec_start = joined.split()
if not exec_start:
    errors.append("no ExecStart")

flags = {}
bare = set()
tokens = exec_start[1:]
i = 0
while i < len(tokens):
    if i + 1 < len(tokens) and not tokens[i + 1].startswith("--"):
        flags[tokens[i]] = tokens[i + 1]
        i += 2
    else:
        bare.add(tokens[i])
        i += 1

want_flags = {
    "--dir": "/var/lib/bazel-remote/data",
    "--max_size": "8",
    "--storage_mode": "uncompressed",
    "--http_address": "10.99.17.10:8080",
    "--grpc_address": "none",
    "--htpasswd_file": "/etc/bazel-remote/htpasswd",
    "--max_blob_size": "2147483648",
}
for flag, value in want_flags.items():
    if flags.get(flag) != value:
        errors.append(f"flag {flag} is {flags.get(flag)!r}, want {value!r}")
for flag in ("--allow_unauthenticated_reads", "--disable_http_ac_validation", "--enable_endpoint_metrics"):
    if flag not in bare:
        errors.append(f"flag {flag} is missing")

for directive in (
    "NoNewPrivileges=true",
    "ProtectSystem=strict",
    "ReadWritePaths=/var/lib/bazel-remote",
    "PrivateTmp=true",
    "ProtectHome=true",
    "CapabilityBoundingSet=",
    "RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX",
    "MemoryMax=768M",
    "ProtectKernelTunables=yes",
    "ProtectKernelModules=yes",
    "ProtectControlGroups=yes",
    "PrivateDevices=yes",
    "RestrictNamespaces=yes",
    "RestrictSUIDSGID=yes",
    "LockPersonality=yes",
    "SystemCallFilter=@system-service",
    "SystemCallArchitectures=native",
    "Restart=on-failure",
    "User=bazel-remote",
):
    if directive not in lines:
        errors.append(f"unit lacks the line {directive!r}")

want_wait = "ExecStartPre=/usr/local/lib/bazel-remote/wait-for-address 10.99.17.10 30"
if want_wait not in lines:
    errors.append(f"unit lacks the line {want_wait!r}")
if "After=network-online.target" not in lines or "Wants=network-online.target" not in lines:
    errors.append("unit must order after and want network-online.target")
if lines.index(want_wait) > lines.index("ExecStartPre=/usr/local/lib/bazel-remote/verify-cas /var/lib/bazel-remote/data /var/lib/bazel-remote/quarantine 3 67108864") if want_wait in lines else False:
    errors.append("the address wait must run before the sweep")
want_pre = "ExecStartPre=/usr/local/lib/bazel-remote/verify-cas /var/lib/bazel-remote/data /var/lib/bazel-remote/quarantine 3 67108864"
if want_pre not in lines:
    errors.append(f"unit lacks the line {want_pre!r}")
if not any(line.startswith("TimeoutStartSec=") for line in lines):
    errors.append("unit lacks TimeoutStartSec for the sweep")

if sentinel in text:
    errors.append("the writer password text reached the unit")
if "{{" in text:
    errors.append("the unit holds an unrendered expression")

tasks = yaml.safe_load(open(tasks_path, encoding="utf-8"))
defaults = yaml.safe_load(open(defaults_path, encoding="utf-8"))

def module_args(task):
    for key, value in task.items():
        if key.startswith("ansible.builtin."):
            return key, value
    return None, None

htpasswd_tasks = 0
for task in tasks:
    name = task.get("name", "?")
    module, args = module_args(task)
    dumped = yaml.safe_dump(task)
    uses_password = "cache_writer_password" in dumped
    is_htpasswd = module == "ansible.builtin.command" and isinstance(args, dict) and "htpasswd" in (args.get("argv") or [])
    if uses_password and task.get("no_log") is not True:
        errors.append(f"task {name!r} reads the password without no_log: true")
    if is_htpasswd:
        htpasswd_tasks += 1
        if task.get("no_log") is not True:
            errors.append(f"htpasswd task {name!r} lacks no_log: true")
        if "cache_writer_password" in " ".join(str(a) for a in args["argv"]):
            errors.append(f"htpasswd task {name!r} puts the password on argv")
        if args.get("stdin") != "{{ cache_writer_password }}":
            errors.append(f"htpasswd task {name!r} does not read the password from stdin")
    elif uses_password and module != "ansible.builtin.assert":
        errors.append(f"task {name!r} uses the password outside htpasswd stdin")
if htpasswd_tasks != 2:
    errors.append(f"expected 2 htpasswd tasks, found {htpasswd_tasks}")

sweep = [t for t in tasks if module_args(t)[0] == "ansible.builtin.copy" and module_args(t)[1].get("src") == "verify-cas"]
if len(sweep) != 1 or sweep[0]["ansible.builtin.copy"].get("owner") != "root" or sweep[0]["ansible.builtin.copy"].get("mode") != "0755":
    errors.append("the sweep must be installed once, root-owned, mode 0755")

downloads = [t for t in tasks if module_args(t)[0] == "ansible.builtin.get_url"]
if len(downloads) != 1 or downloads[0]["ansible.builtin.get_url"].get("checksum") != "sha256:{{ cache_service_sha256 }}":
    errors.append("the binary download must be one get_url with checksum sha256:{{ cache_service_sha256 }}")
if defaults.get("cache_service_sha256") != "62e236bf8396e69396928e0d0c32062fbd5575f20fe55dc10a82eb791297e1a0":
    errors.append("cache_service_sha256 is not the pinned digest")
if defaults.get("cache_service_version") != "2.6.2":
    errors.append("cache_service_version is not 2.6.2")

if errors:
    print("\n".join(errors))
    sys.exit(1)
PY

verify() {
  local dir="$1" out="$2"
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
    ansible localhost -c local -m ansible.builtin.template \
      -a "src=$dir/templates/bazel-remote.service.j2 dest=$out" \
      -e "@$dir/defaults/main.yml" -e "@$work/vars.json" > "$work/ansible.log" 2>&1 \
    || { cat "$work/ansible.log" >&2; echo "FAIL: the unit did not render" >&2; return 2; }
  python3 -I "$work/check.py" "$out" "$dir/tasks/main.yml" "$dir/defaults/main.yml" "$sentinel"
}

verify "$role" "$work/bazel-remote.service" || { echo "FAIL: the role does not meet the cache service contract" >&2; exit 1; }
echo "ok: the rendered unit and the tasks meet the contract"

mutate() {
  local label="$1" file="$2" expr="$3" copy="$work/mut"
  rm -rf "$copy"
  cp -r "$role" "$copy"
  sed -i -e "$expr" "$copy/$file"
  if cmp -s "$role/$file" "$copy/$file"; then
    echo "FAIL: mutation '$label' changed nothing" >&2
    exit 1
  fi
  if verify "$copy" "$work/mut.service" > "$work/mut.log" 2>&1; then
    echo "FAIL: mutation '$label' was not caught" >&2
    exit 1
  fi
  echo "ok: mutation '$label' is rejected: $(head -n1 "$work/mut.log")"
}

mutate "drop allow_unauthenticated_reads" templates/bazel-remote.service.j2 '/--allow_unauthenticated_reads/d'
mutate "drop htpasswd_file" templates/bazel-remote.service.j2 '/--htpasswd_file/d'
mutate "drop the address wait from the unit" templates/bazel-remote.service.j2 '/wait-for-address/d'
mutate "drop the sweep from the unit" templates/bazel-remote.service.j2 '/^ExecStartPre=/d'
mutate "drop the grpc off switch" templates/bazel-remote.service.j2 '/--grpc_address none/d'
mutate "drop the syscall filter" templates/bazel-remote.service.j2 '/^SystemCallFilter=/d'
mutate "loosen ProtectSystem" templates/bazel-remote.service.j2 's/^ProtectSystem=strict/ProtectSystem=full/'
mutate "put the password in the unit" templates/bazel-remote.service.j2 '/^\[Install\]/i Environment=PW={{ cache_writer_password }}'
mutate "drop no_log" tasks/main.yml '/^  no_log: true/d'
mutate "unpin the digest" defaults/main.yml 's/^cache_service_sha256: .*/cache_service_sha256: 0000000000000000000000000000000000000000000000000000000000000000/'
