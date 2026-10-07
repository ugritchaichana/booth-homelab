#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${HYPERV_GUEST_ROLE_DIR:-$repo/iac/ansible/roles/hyperv_guest}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible-playbook >/dev/null || { echo "ERROR: ansible is not installed" >&2; exit 2; }
[ -f "$role/tasks/main.yml" ] || { echo "ERROR: no tasks/main.yml under $role" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/lib/role-fakes.sh"
fake_role_prepare hyperv_guest "$role" modprobe
ROLE_NAME=hyperv_guest BASE_SCENARIO="$work/base.json"

MODULES_CLEAN="hv_vmbus 163840 3 hv_netvsc,hv_storvsc, - Live 0x0000000000000000
hv_netvsc 126976 0 - Live 0x0000000000000000"
cat > "$work/base.json" <<JSON
{"package_facts": [{"result": {"ansible_facts": {"packages": {"openssh-server": [{"name": "openssh-server"}], "qemu-guest-agent": [{"name": "qemu-guest-agent"}]}}}}],
 "service_facts": [{"result": {"ansible_facts": {"services": {"ssh.service": {"name": "ssh.service", "state": "running"}, "hv-kvp-daemon.service": {"name": "hv-kvp-daemon.service", "state": "stopped"}}}}}],
 "slurp": [{"when": "/proc/modules", "result": {"content": "$(b64 "$MODULES_CLEAN")"}}],
 "command": [{"when": "modprobe", "result": {"rc": 0, "stdout": "install /bin/false", "stderr": ""}}]}
JSON

DAEMON_MSG="host-to-guest channel"
LOADED_MSG="blocked Hyper-V module is loaded"

run happy
should_pass "a clean guest"
verdict "the drop-in blocks hv_sock by install override" "$(cat "$out/copy/homelab-hyperv-blocked.conf")" "install hv_sock /bin/false"
verdict "the drop-in targets the modprobe.d directory as root, mode 0644" \
  "$(call_count copy '"dest": "/etc/modprobe.d/homelab-hyperv-blocked.conf"' '"owner": "root"' '"group": "root"' '"mode": "0644"')" 1
verdict "hv_sock is unloaded" "$(call_count modprobe '"name": "hv_sock"' '"state": "absent"')" 1
verdict "modprobe is asked what it would do for hv_sock" "$(call_count command 'modprobe -n -v hv_sock')" 1

run two-modules "" -e '{"hyperv_guest_blocked_modules": ["hv_sock", "vsock"]}'
should_pass "two blocked modules"
verdict "the drop-in carries one install line per module" "$(tr '\n' '|' < "$out/copy/homelab-hyperv-blocked.conf")" "install hv_sock /bin/false|install vsock /bin/false|"
verdict "every blocked module is unloaded" "$(call_count modprobe '"state": "absent"')" 2
verdict "every blocked module is planned" "$(call_count command 'modprobe -n -v')" 2

LIST_MSG="must be a list that contains hv_sock"
for bad in '[]' '["vsock"]' '"hv_sock"' 'null'; do
  run "bad-list-$bad" "" -e "{\"hyperv_guest_blocked_modules\": $bad}"
  should_fail "a blocked module list of $bad" "$LIST_MSG"
  verdict "a blocked module list of $bad writes no drop-in" "$(call_count copy)" 0
done

run daemon-package-installed '{"package_facts": [{"result": {"ansible_facts": {"packages": {"hyperv-daemons": [{}]}}}}]}'
should_fail "an installed hyperv-daemons package" "$DAEMON_MSG"
run init-package-installed '{"package_facts": [{"result": {"ansible_facts": {"packages": {"hv-kvp-daemon-init": [{}]}}}}]}'
should_fail "an installed hv-kvp-daemon-init package" "$DAEMON_MSG"
for unit in hv-kvp-daemon.service hv_vss_daemon.service hv-fcopy-daemon.service; do
  run "running-$unit" "{\"service_facts\": [{\"result\": {\"ansible_facts\": {\"services\": {\"$unit\": {\"name\": \"$unit\", \"state\": \"running\"}}}}}]}"
  should_fail "a running $unit" "$DAEMON_MSG"
done
run no-services '{"service_facts": [{"result": {"ansible_facts": {"services": {}}}}]}'
should_pass "a guest with no services"
run unrelated-hv-service '{"service_facts": [{"result": {"ansible_facts": {"services": {"hv-other.service": {"name": "x", "state": "running"}, "hvkvp-helper.service": {"name": "y", "state": "running"}}}}}]}'
should_pass "a running service that only resembles the daemon names"

run hv-sock-loaded "{\"slurp\": [{\"when\": \"/proc/modules\", \"result\": {\"content\": \"$(b64 "$MODULES_CLEAN
hv_sock 24576 0 - Live 0x0000000000000000")\"}}]}"
should_fail "a loaded hv_sock" "$LOADED_MSG"
run hv-sock-first-line "{\"slurp\": [{\"when\": \"/proc/modules\", \"result\": {\"content\": \"$(b64 "hv_sock 24576 0 - Live 0x0")\"}}]}"
should_fail "hv_sock as the only loaded module" "$LOADED_MSG"
run empty-modules "{\"slurp\": [{\"when\": \"/proc/modules\", \"result\": {\"content\": \"\"}}]}"
should_pass "an empty module list"
run second-module-loaded "{\"slurp\": [{\"when\": \"/proc/modules\", \"result\": {\"content\": \"$(b64 "vsock 1 0 - Live 0x0")\"}}]}" -e '{"hyperv_guest_blocked_modules": ["hv_sock", "vsock"]}'
should_fail "the second blocked module loaded" "$LOADED_MSG"

run plan-would-insmod '{"command": [{"when": "modprobe", "result": {"rc": 0, "stdout": "insmod /lib/modules/6.12.0-amd64/kernel/net/vmw_vsock/hv_sock.ko", "stderr": ""}}]}'
should_fail "a modprobe plan that loads the module" "$LOADED_MSG"
run plan-empty '{"command": [{"when": "modprobe", "result": {"rc": 0, "stdout": "", "stderr": ""}}]}'
should_fail "an empty modprobe plan" "$LOADED_MSG"
run plan-second-bad '{"command": [{"when": "-v vsock", "result": {"rc": 0, "stdout": "insmod vsock.ko", "stderr": ""}}]}' -e '{"hyperv_guest_blocked_modules": ["hv_sock", "vsock"]}'
should_fail "one bad plan among several" "$LOADED_MSG"
run plan-fails '{"command": [{"when": "modprobe", "result": {"rc": 1, "stdout": "", "stderr": "modprobe: FATAL"}}]}'
verdict "a failing modprobe query stops the play" "$([ "$rc" -ne 0 ] && echo stopped || echo continued)" stopped

run unload-fails '{"modprobe": [{"result": {"failed": true, "msg": "Module hv_sock is in use"}}]}'
verdict "a module that cannot be unloaded stops the play" "$([ "$rc" -ne 0 ] && echo stopped || echo continued)" stopped
verdict "nothing is asserted after a failed unload" "$(call_count slurp)" 0

python3 -I - "$role/defaults/main.yml" <<'PY' || failures=$((failures + 1))
import re
import sys
import yaml

values = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
errors = []
if "hv_sock" not in values["hyperv_guest_blocked_modules"]:
    errors.append("hv_sock is not blocked by default")
if not {"hyperv-daemons", "hv-kvp-daemon-init"} <= set(values["hyperv_guest_forbidden_packages"]):
    errors.append("the default forbidden packages lose the daemon packages")
pattern = re.compile(values["hyperv_guest_forbidden_service_pattern"])
for unit in ("hv-kvp-daemon.service", "hv-vss-daemon.service", "hv-fcopy-daemon.service", "hv_kvp_daemon.service"):
    if not pattern.match(unit):
        errors.append("the service pattern does not match " + unit)
for unit in ("ssh.service", "hv-other.service", "qemu-guest-agent.service"):
    if pattern.match(unit):
        errors.append("the service pattern also matches " + unit)
for message in errors:
    print("FAIL: " + message)
sys.exit(1 if errors else 0)
PY

finish "hyperv_guest drop-in, daemon guard, loaded-module guard and modprobe-plan guard behave as expected"
