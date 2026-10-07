#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${PVE_HOST_ROLE_DIR:-$repo/iac/ansible/roles/pve_host}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible-playbook >/dev/null || { echo "ERROR: ansible is not installed" >&2; exit 2; }
[ -f "$role/tasks/main.yml" ] || { echo "ERROR: no tasks/main.yml under $role" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/lib/role-fakes.sh"
fake_role_prepare pve_host "$role" uname grep proxmox-boot-tool
ROLE_NAME=pve_host BASE_SCENARIO="$work/base.json"

NEW=7.0.14-20-pve
AUTO_LIST="Manually selected kernels:
None.

Automatically selected kernels:
6.17.2-1-pve
$NEW
7.0.14-4-pve"
cat > "$work/base.json" <<JSON
{"stat": [{"result": {"stat": {"exists": false}}}],
 "command": [{"when": "uname", "result": {"rc": 0, "stdout": "$NEW"}},
             {"when": "proxmox-boot-tool", "result": {"rc": 0, "stdout": $(jstr "$AUTO_LIST")}},
             {"when": "grep -c", "result": {"rc": 0, "stdout": "8"}}],
 "slurp": [{"when": "kvm_amd", "result": {"content": "$(b64 "Y
")"}},
           {"when": "kvm_intel", "result": {"failed": true, "msg": "file not found"}}]}
JSON
KVM_OFF='{"slurp": [{"when": "kvm_amd", "result": {"content": "'"$(b64 "N
")"'"}}]}'
KERNEL_MSG="The boot default differs from the running kernel"
NO_KERNEL_MSG="lists no kernel to boot"
KVM_MSG="Nested KVM is off"
SUITE='"suites": "trixie"'
KEYRING='"signed_by": "/usr/share/keyrings/proxmox-archive-keyring.gpg"'

TASKS_FROM=repos run repos-only
should_pass "the repository tasks alone (bootstrap path)"
verdict "pve-enterprise is disabled over https with the keyring" \
  "$(call_count deb822_repository '"name": "pve-enterprise"' '"enabled": false' '"uris": "https://enterprise.proxmox.com/debian/pve"' "$SUITE" "$KEYRING")" 1
verdict "the ceph enterprise repository is disabled over https with the keyring" \
  "$(call_count deb822_repository '"name": "ceph"' '"enabled": false' '"uris": "https://enterprise.proxmox.com/debian/ceph-squid"' "$SUITE" "$KEYRING")" 1
verdict "pve-no-subscription is the only enabled repository, signed by the keyring" \
  "$(call_count deb822_repository '"name": "pve-no-subscription"' '"enabled": true' '"components": "pve-no-subscription"' "$KEYRING")" 1
verdict "exactly three repositories are written" "$(call_count deb822_repository)" 3
verdict "no repository is marked trusted or unsigned" "$(call_count deb822_repository 'trusted')" 0
verdict "no apt refresh without a repository change" "$(call_count apt)" 0

for changed in pve-enterprise ceph pve-no-subscription; do
  TASKS_FROM=repos run "changed-$changed" "{\"deb822_repository\": [{\"when\": \"\\\"name\\\": \\\"$changed\\\"\", \"result\": {\"changed\": true}}]}"
  verdict "a changed $changed refreshes the apt cache once" "$(call_count apt '"update_cache": true')" 1
done
TASKS_FROM=repos run suite-override "" -e pve_repo_suite=forky
verdict "a suite override reaches all three repositories" "$(call_count deb822_repository '"suites": "forky"')" 3
TASKS_FROM=repos run keyring-override "" -e pve_host_keyring=/usr/share/keyrings/other.gpg
verdict "a keyring override reaches all three repositories" "$(call_count deb822_repository '"signed_by": "/usr/share/keyrings/other.gpg"')" 3
TASKS_FROM=repos run repo-write-fails '{"deb822_repository": [{"result": {"failed": true, "msg": "cannot write"}}]}'
verdict "a failed repository write stops before any apt call" "$([ "$rc" -ne 0 ] && echo stopped || echo continued)$(call_count apt)" stopped0

SET_MSG="must be non-empty"
for bad in 'pve_repo_suite|""' 'pve_repo_suite|"  "' 'pve_repo_suite|13' 'pve_host_keyring|""' 'pve_host_keyring|"  "'; do
  TASKS_FROM=repos run "bad-${bad%%|*}" "" -e "{\"${bad%%|*}\": ${bad#*|}}"
  should_fail "${bad%%|*} set to ${bad#*|}" "$SET_MSG"
  verdict "${bad%%|*} set to ${bad#*|} writes no repository and runs no apt" "$(call_count deb822_repository)$(call_count apt)" 00
done
run empty-suite-main "" -e '{"pve_repo_suite": ""}'
should_fail "an empty suite in the full role" "$SET_MSG"
verdict "the full role runs no apt call for an empty suite" "$(call_count apt)" 0

run happy
should_pass "a host already on its boot kernel"
verdict "the upgrade is a full upgrade with a cache refresh" "$(call_count apt '"upgrade": "full"' '"update_cache": true')" 1
verdict "no reboot when nothing asks for one" "$(call_count reboot)" 0
verdict "the repositories are configured before the upgrade" "$(call_count deb822_repository)" 3

run marker-reboot '{"stat": [{"result": {"stat": {"exists": true}}}]}'
should_pass "a reboot-required marker with the same kernel"
verdict "the marker forces one reboot that waits for pveversion" "$(call_count reboot '"test_command": "pveversion"' '"reboot_timeout": 900')" 1
run kernel-reboot '{"command": [{"when": "uname", "seq": [{"rc": 0, "stdout": "6.17.2-1-pve"}, {"rc": 0, "stdout": "7.0.14-20-pve"}]}]}'
should_pass "a new boot kernel"
verdict "a running kernel that is not the boot default reboots once" "$(call_count reboot)" 1
run kernel-reboot-timeout '{"stat": [{"result": {"stat": {"exists": true}}}]}' -e '{"pve_host_reboot_timeout": 1200}'
verdict "the reboot timeout variable reaches the reboot" "$(call_count reboot '"reboot_timeout": 1200')" 1
run still-wrong-kernel '{"command": [{"when": "uname", "seq": [{"rc": 0, "stdout": "6.17.2-1-pve"}, {"rc": 0, "stdout": "6.17.2-1-pve"}]}]}'
should_fail "a host that still runs the old kernel after the reboot" "$KERNEL_MSG"

PINNED_LIST="$AUTO_LIST

Pinned kernel:
6.17.2-1-pve"
run pinned-kernel "{\"command\": [$(rule proxmox-boot-tool "$PINNED_LIST"), {\"when\": \"uname\", \"result\": {\"rc\": 0, \"stdout\": \"6.17.2-1-pve\"}}]}"
should_pass "a pinned kernel older than the newest installed"
verdict "the pinned kernel wins over the newest, so no reboot" "$(call_count reboot)" 0
run version-sort "{\"command\": [{\"when\": \"uname\", \"result\": {\"rc\": 0, \"stdout\": \"7.0.14-20-pve\"}}]}"
should_pass "the highest version among 6.17.2-1, 7.0.14-4 and 7.0.14-20"
verdict "version order, not text order, picks 7.0.14-20 and no reboot follows" "$(call_count reboot)" 0
run manual-kernel "{\"command\": [$(rule proxmox-boot-tool "Manually selected kernels:
8.0.1-1-pve

Automatically selected kernels:
7.0.14-20-pve"), {\"when\": \"uname\", \"result\": {\"rc\": 0, \"stdout\": \"8.0.1-1-pve\"}}]}"
should_pass "a manually selected kernel counts as a candidate"
verdict "the manual 8.0.1-1 is the default, so no reboot" "$(call_count reboot)" 0
run no-kernel "{\"command\": [$(rule proxmox-boot-tool "Manually selected kernels:
None.

Automatically selected kernels:
None.")]}"
should_fail "a kernel list with no kernel" "$NO_KERNEL_MSG"
verdict "nothing reboots when no kernel was found" "$(call_count reboot)" 0
run empty-kernel-list "{\"command\": [$(rule proxmox-boot-tool "")]}"
should_fail "an empty kernel list" "$NO_KERNEL_MSG"
run boot-tool-fails "{\"command\": [$(rule proxmox-boot-tool "" 1)]}"
verdict "a failing proxmox-boot-tool stops the play" "$([ "$rc" -ne 0 ] && echo stopped || echo continued)$(call_count reboot)" stopped0

run nested-intel '{"slurp": [{"when": "kvm_amd", "result": {"failed": true, "msg": "file not found"}}, {"when": "kvm_intel", "result": {"content": "'"$(b64 "1
")"'"}}]}'
should_pass "nested KVM reported only by kvm_intel as 1"
run nested-off "$KVM_OFF"
should_fail "kvm_amd nested reading N" "$KVM_MSG"
run nested-zero '{"slurp": [{"when": "kvm_amd", "result": {"content": "'"$(b64 "0
")"'"}}]}'
should_fail "kvm_amd nested reading 0" "$KVM_MSG"
run nested-no-module '{"slurp": [{"when": "kvm_amd", "result": {"failed": true, "msg": "file not found"}}]}'
should_fail "no kvm module parameter readable at all" "$KVM_MSG"
run nested-no-flags '{"command": [{"when": "grep -c", "result": {"rc": 1, "stdout": "0"}}]}'
should_fail "no vmx or svm CPU flag (grep rc 1)" "$KVM_MSG"
run grep-error '{"command": [{"when": "grep -c", "result": {"rc": 2, "stdout": "", "stderr": "grep: /proc/cpuinfo"}}]}'
verdict "a grep error (rc 2) stops the play at the grep, not at the nested assert"   "$([ "$rc" -ne 0 ] && echo stopped || echo continued)$(grep -cF "$KVM_MSG" "$work/run.log" || true)" stopped0
run nested-no-paths "" -e '{"pve_host_kvm_parameter_paths": []}'
should_fail "an empty list of module parameter paths" "$KVM_MSG"
run nested-unexpected-value '{"slurp": [{"when": "kvm_amd", "result": {"content": "'"$(b64 "2")"'"}}]}'
should_fail "kvm_amd nested reading an unexpected value" "$KVM_MSG"

python3 -I - "$role/defaults/main.yml" "$role/tasks/main.yml" <<'PY' || failures=$((failures + 1))
import sys
import yaml

values = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
upgrade = next(t for t in yaml.safe_load(open(sys.argv[2], encoding="utf-8")) if "ansible.builtin.apt" in t)
errors = []
if upgrade.get("async") != "{{ pve_host_upgrade_timeout }}" or not upgrade.get("poll"):
    errors.append("the full upgrade lost its async and poll settings")
if upgrade.get("environment", {}).get("DEBIAN_FRONTEND") != "noninteractive":
    errors.append("the full upgrade no longer runs non-interactively")
if "pve_repo_suite" not in values["pve_host_suite"] or "trixie" not in values["pve_host_suite"]:
    errors.append("the default suite is not pve_repo_suite with a trixie fallback")
if not values["pve_host_keyring"].endswith("proxmox-archive-keyring.gpg"):
    errors.append("the default keyring is not the Proxmox archive keyring")
if not {"/sys/module/kvm_amd/parameters/nested", "/sys/module/kvm_intel/parameters/nested"} <= set(values["pve_host_kvm_parameter_paths"]):
    errors.append("the nested parameter paths lose the AMD or Intel module")
if values["pve_host_reboot_timeout"] <= 0 or values["pve_host_upgrade_timeout"] <= 0:
    errors.append("the reboot and upgrade timeouts must be positive")
for message in errors:
    print("FAIL: " + message)
sys.exit(1 if errors else 0)
PY

finish "pve_host repositories, upgrade, kernel choice, reboot and nested-KVM guards behave as expected"
