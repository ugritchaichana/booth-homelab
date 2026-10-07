#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="$repo/iac/ansible/roles/pve_templates"
tpl="${TEMPLATE_BIN:-$role/files/homelab-template.py}"
guest_step="$role/files/homelab-template-guest.py"
fake="$repo/tests/isolation/lib/fake-pve.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook is not installed" >&2; exit 2; }
command -v ssh-keygen >/dev/null || { echo "ERROR: ssh-keygen is not installed" >&2; exit 2; }

mkdir -p "$work/bin"
for name in pvesh qm pct lvs systemctl logger; do
  printf '#!/bin/sh\nexec python3 -I "%s" %s "$@"\n' "$fake" "$name" > "$work/bin/$name"
  chmod +x "$work/bin/$name"
done
export PATH="$work/bin:$PATH"

python3 -I - "$repo/iac/inventory/hosts.yml" "$work/vars.json" "$role" <<'PY'
import json, sys, yaml
hosts = yaml.safe_load(open(sys.argv[1]))["all"]["children"]["pve_hosts"]["hosts"]["pve01"]
json.dump({"guest_network": hosts["guest_network"], "pve_node_name": "n1", "role_path": sys.argv[3]}, open(sys.argv[2], "w"))
PY
cat > "$work/render.yml" <<YML
---
- name: Render the orchestrator configuration the role installs
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - $role/defaults/main.yml
  tasks:
    - name: Write the rendered configuration
      ansible.builtin.copy:
        content: "{{ pve_templates_config | to_nice_json }}"
        dest: "$work/base-config.json"
        mode: "0600"
YML
ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
  ansible-playbook "$work/render.yml" -e "@$work/vars.json" > "$work/render.log" 2>&1 \
  || { cat "$work/render.log" >&2; echo "FAIL: the role configuration did not render" >&2; exit 1; }

failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$3', wanted '$2'"; failures=$((failures + 1)); fi
}
has() { if grep -q -- "$3" "$2"; then echo "PASS $1"; else echo "FAIL $1: no line matching '$3' in $(basename "$2")"; failures=$((failures + 1)); fi; }
hasnt() { if grep -q -- "$3" "$2"; then echo "FAIL $1: unexpected line matching '$3' in $(basename "$2")"; failures=$((failures + 1)); else echo "PASS $1"; fi; }
count() { grep -cE -- "$1" "$2" || true; }

case_dir=""
new_case() {
  case_dir="$work/case-$1"
  rm -rf "$case_dir"
  mkdir -p "$case_dir/state" "$case_dir/work" "$case_dir/common" "$case_dir/bundles"
  cp -r "$role/files/common/." "$case_dir/common/"
  cat > "$case_dir/world.json" <<JSON
{"node": "n1", "guests": {}, "lvs": {"data_percent": 40, "metadata_percent": 10}, "local_avail_gib": 20}
JSON
  python3 -I - "$work/base-config.json" "$case_dir" <<'PY'
import getpass, json, sys
cfg = json.load(open(sys.argv[1]))
case = sys.argv[2]
cfg.update({"state_dir": case + "/state", "work_dir": case + "/work", "bundle_common_dir": case + "/common", "bundle_root_dir": case + "/bundles", "guest_user": getpass.getuser(), "require_root": False})
json.dump(cfg, open(case + "/config.json", "w"))
PY
  : > "$case_dir/calls"
  : > "$case_dir/journal"
}

rc=0
tplrun() {
  set +e
  FAKE_WORLD="$case_dir/world.json" FAKE_CALLS="$case_dir/calls" FAKE_JOURNAL="$case_dir/journal" FAKE_WORK_DIR="$case_dir/work" GUEST_STEP="$guest_step" \
    python3 -I "$tpl" --config "$case_dir/config.json" "$@" > "$case_dir/out.log" 2>&1
  rc=$?
  set -e
}

world_get() {
  python3 -I - "$case_dir/world.json" "$1" <<'PY'
import json, sys
guests = json.load(open(sys.argv[1]))["guests"]
expr = sys.argv[2]
print(eval(expr, {"g": guests}))
PY
}
state_get() {
  python3 -I - "$case_dir/state/$1.json" "$2" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {"s": s}))
PY
}
world_edit() {
  python3 -I - "$case_dir/world.json" "$1" <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))
exec(sys.argv[2], {"w": w})
json.dump(w, open(sys.argv[1], "w"))
PY
}
config_edit() {
  python3 -I - "$case_dir/config.json" "$1" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
exec(sys.argv[2], {"c": c})
json.dump(c, open(sys.argv[1], "w"))
PY
}
guest_names() { world_get "sorted('%s:%s' % (k, v['name']) for k, v in g.items())"; }
tags_of() { world_get "g['$1']['tags'] if '$1' in g else 'absent'"; }
tagset() { world_get "';'.join(sorted(g['$1']['tags'].split(';')))"; }
sorted_tags() { printf '%s' "$1" | tr ';' '\n' | LC_ALL=C sort | paste -sd';' -; }

lxc=lxc-runner
vm=vm-docker
build_ok() {
  tplrun build "$1"
  expect "$2: build exits 0" 0 "$rc"
  if [ "$rc" -ne 0 ]; then sed 's/^/  | /' "$case_dir/out.log"; fi
}

echo "== happy path, both classes, three builds"
for cls in $lxc $vm; do
  new_case "happy-$cls"
  base=$([ "$cls" = "$lxc" ] && echo 9200 || echo 9300)
  printf '{"os": "debian 13", "tool": "1.0"}\n' > "$case_dir/manifest.json"
  export FAKE_MANIFEST_FILE="$case_dir/manifest.json"
  build_ok "$cls" "$cls v1"
  want_sha="$(sha256sum "$case_dir/manifest.json" | cut -d' ' -f1)"
  expect "$cls v1: lands on the first free VMID of the block" "$((base + 2)):tmpl-$cls-v1" "$(guest_names | tr -d "[]' " | cut -d, -f1)"
  expect "$cls v1: carries marker, class, version and current tags" "$(sorted_tags "current;homelab-template;$cls;v1")" "$(tagset $((base + 2)))"
  expect "$cls v1: is a template in the templates pool" "1 templates" "$(world_get "str(g['$((base + 2))']['template']) + ' ' + g['$((base + 2))']['pool']")"
  expect "$cls v1: description holds only host-chosen values and the manifest sha256" "1" "$(world_get "int(g['$((base + 2))']['config']['description'].startswith('class=$cls version=1 built=') and g['$((base + 2))']['config']['description'].endswith('manifest_sha256=$want_sha'))")"
  expect "$cls v1: no key, address or inbound rule is left in the template" "[{'type': 'group', 'action': 'guest-egress', 'enable': '1'}]" "$(world_get "g['$((base + 2))']['fw_rules']")"
  expect "$cls v1: no ssh or address key is left in the template config" "0" "$(world_get "len([k for k in g['$((base + 2))']['config'] if k in ('sshkeys','ipconfig0','cicustom','ciuser','nameserver')])")"
  expect "$cls v1: the verification clone is gone" "1" "$(world_get "len(g)")"
  expect "$cls v1: the stored manifest is the guest's file" "$want_sha" "$(sha256sum "$case_dir/state/manifests/$cls/v1.json" | cut -d' ' -f1)"
  expect "$cls v1: the work directory with the key is removed" "absent" "$([ -e "$case_dir/work/build" ] && echo present || echo absent)"
  has "$cls v1: the journal logs the read-back before the first start" "$case_dir/out.log" "READBACK ok vmid=$((base + 2)) kind=.* before first start"
  expect "$cls v1: the read-back line comes before the start line" "1" "$(awk '/READBACK ok .* before first start/{r=NR} /START vmid=/{s=NR} END{print (r>0 && s>r)?1:0}' "$case_dir/out.log")"
  has "$cls v1: promotion is journaled" "$case_dir/out.log" "PROMOTED class=$cls first version v1"
  hasnt "$cls v1: the build guest was never given a pool" "$case_dir/calls" "--pool"
  expect "$cls v1: a linked clone was requested" "1" "$(count 'clone .* --full 0' "$case_dir/calls")"
  expect "$cls v1: state current is 1, previous none" "1 None" "$(state_get "$cls" "str(s['current']) + ' ' + str(s['previous'])")"

  build_ok "$cls" "$cls v2"
  expect "$cls v2: current moved to 2, previous recorded as 1" "2 1" "$(state_get "$cls" "str(s['current']) + ' ' + str(s['previous'])")"
  expect "$cls v2: exactly one current tag, on v2" "$((base + 3))" "$(world_get "[k for k, v in g.items() if 'current' in v['tags'].split(';')][0]")"
  expect "$cls v2: v1 lost the current tag and kept its version tags" "$(sorted_tags "homelab-template;$cls;v1")" "$(tagset $((base + 2)))"

  build_ok "$cls" "$cls v3"
  expect "$cls v3: retention keeps current and previous only" "$((base + 3)),$((base + 4))" "$(world_get "','.join(sorted(k for k in g))")"
  has "$cls v3: the deletion of v1 is journaled" "$case_dir/out.log" "RETENTION destroyed vmid=$((base + 2)) v1"

  tplrun status "$cls"
  expect "$cls: status exits 0" 0 "$rc"
  expect "$cls: status prints exactly one current line for the class" "1" "$(count "^class=$cls current=v3 vmid=$((base + 4))" "$case_dir/out.log")"
  tplrun status
  expect "status without a class fails closed while the other class has no version" 1 "$rc"
done
unset FAKE_MANIFEST_FILE

echo "== rollback, then build keeps the rollback target"
new_case rollback
build_ok $lxc "v1"; build_ok $lxc "v2"
tplrun rollback $lxc
expect "rollback exits 0" 0 "$rc"
expect "rollback swaps current and previous in state" "1 2" "$(state_get $lxc "str(s['current']) + ' ' + str(s['previous'])")"
expect "rollback moves the current tag to v1" "9202" "$(world_get "[k for k, v in g.items() if 'current' in v['tags'].split(';')][0]")"
has "rollback is journaled" "$case_dir/journal" "ROLLBACK class=$lxc current v2 -> v1"
build_ok $lxc "v3 after rollback"
expect "after rollback and a build: current is 3, previous is the rollback target 1" "3 1" "$(state_get $lxc "str(s['current']) + ' ' + str(s['previous'])")"
expect "after rollback and a build: the rollback target v1 survives and v2 is retired" "9202,9204" "$(world_get "','.join(sorted(g))")"

echo "== retention never deletes a version with a dependent clone"
new_case dependents
build_ok $lxc "v1"; build_ok $lxc "v2"
world_edit "w['guests']['9500'] = {'type': 'lxc', 'name': 'runner-clone', 'status': 'running', 'template': 0, 'pool': 'homelab', 'tags': '', 'config': {}, 'fw_options': {}, 'fw_rules': [], 'ipsets': {}, 'origin': 9202}"
build_ok $lxc "v3 with a live clone of v1"
has "retention refuses v1 because a clone depends on it" "$case_dir/out.log" "RETENTION kept vmid=9202: dependent clone volumes vm-9500-disk-0"
expect "v1 still exists" "yes" "$(world_get "'yes' if '9202' in g else 'no'")"

echo "== a leftover guest is destroyed and never counted as a version"
new_case leftover
world_edit "w['guests']['9207'] = {'type': 'lxc', 'name': 'build-lxc-runner-v7', 'status': 'stopped', 'template': 0, 'pool': '', 'tags': 'homelab-template;lxc-runner;v7;current', 'config': {}, 'fw_options': {}, 'fw_rules': [], 'ipsets': {}, 'origin': None}"
tplrun status $lxc
expect "a leftover with version and current tags is not a version: status refuses" 1 "$rc"
has "status names the missing current" "$case_dir/out.log" "class=$lxc ERROR current-count=0"
build_ok $lxc "build over a leftover"
has "the leftover was destroyed first" "$case_dir/calls" "pct destroy 9207"
expect "the new version is v1, not v8" "1" "$(state_get $lxc "s['current']")"

echo "== refusals before anything is created"
for case_name in "metadata_percent:85:metadata_percent 85.00 is above 70" "data_percent:75:data_percent 75.00 is above 70"; do
  key="${case_name%%:*}"; rest="${case_name#*:}"; value="${rest%%:*}"; message="${rest#*:}"
  new_case "refuse-$key"
  world_edit "w['lvs']['$key'] = $value"
  tplrun build $lxc
  expect "thin pool $key over the threshold refuses with exit 3" 3 "$rc"
  has "thin pool $key refusal is journaled" "$case_dir/out.log" "REFUSED .*$message"
  expect "thin pool $key refusal creates nothing" 0 "$(count 'create' "$case_dir/calls")"
done
new_case refuse-local
world_edit "w['local_avail_gib'] = 3"
tplrun build $lxc
expect "local storage below the minimum refuses with exit 3" 3 "$rc"
expect "local storage refusal creates nothing" 0 "$(count 'create' "$case_dir/calls")"
new_case refuse-lock
python3 -I - "$case_dir/state/lock" <<'PY' &
import fcntl, sys, time
handle = open(sys.argv[1], "w")
fcntl.flock(handle, fcntl.LOCK_EX)
time.sleep(30)
PY
holder=$!
sleep 1
tplrun build $lxc
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
expect "a second build while one holds the lock exits 3" 3 "$rc"
has "the lock refusal is journaled" "$case_dir/out.log" "another homelab-template run holds the lock"
new_case unknown-class
tplrun build nonsense
expect "an unknown class exits 2" 2 "$rc"

echo "== pass-marker gate: no pass marker, no conversion"
for scenario in nopass wrongid symlink bigmanifest fail; do
  new_case "gate-$scenario"
  export FAKE_GUEST="$scenario"
  tplrun build $vm
  unset FAKE_GUEST
  expect "scenario $scenario: the build fails with exit 1" 1 "$rc"
  expect "scenario $scenario: no template conversion was requested" 0 "$(count 'qm template' "$case_dir/calls")"
  expect "scenario $scenario: the build guest is destroyed" "1" "$(count 'qm destroy 9302' "$case_dir/calls")"
  expect "scenario $scenario: nothing is promoted" "None" "$(state_get $vm "s['current']")"
  expect "scenario $scenario: the key directory is removed" "absent" "$([ -e "$case_dir/work/build" ] && echo present || echo absent)"
done
has "wrong build id is named" "$work/case-gate-wrongid/out.log" "pass marker does not carry build id"

echo "== a failure while the guest is being set up leaves no guest behind"
new_case setup-fails
FAIL_CALLS="pvesh create" tplrun build $lxc
expect "a firewall call that fails stops the build with exit 1" 1 "$rc"
expect "the half-built guest is destroyed" 1 "$(count '^pct destroy 9202' "$case_dir/calls")"
expect "the half-built guest was never started" 0 "$(count '^pct start' "$case_dir/calls")"

echo "== a planted .credentials in the guest means no conversion (real finalize.sh in the loop)"
scan_case() {
  new_case "$1"
  mkdir -p "$case_dir/guestroot/var/lib/homelab-build" "$case_dir/guestroot/opt/actions-runner" "$case_dir/guestroot/etc"
  echo '{"os": "debian 13"}' > "$case_dir/guestroot/var/lib/homelab-build/manifest.json"
  [ "$2" != planted ] || echo '{"scheme": "OAuth"}' > "$case_dir/guestroot/opt/actions-runner/.credentials"
  FAKE_GUEST=scan FAKE_SCAN_ROOT="$case_dir/guestroot" FINALIZE_SCRIPT="${FINALIZE_SCRIPT:-$role/files/common/finalize.sh}" tplrun build $vm
}
scan_case scan-planted planted
expect "a planted .credentials fails the build" 1 "$rc"
expect "a planted .credentials: no conversion was requested" 0 "$(count 'qm template' "$case_dir/calls")"
expect "a planted .credentials: the build guest is destroyed" 1 "$(count 'qm destroy 9302' "$case_dir/calls")"
expect "a planted .credentials: nothing is promoted" "None" "$(state_get $vm "s['current']")"
scan_case scan-clean clean
expect "the same guest without .credentials converts and promotes" "0 1" "$rc $(state_get $vm "s['current']")"
expect "the clean control did request the conversion" 1 "$(count 'qm template 9302' "$case_dir/calls")"

echo "== verification: linked clone and the class hook"
new_case verify-full-clone
export FAKE_CLONE_FULL=1
tplrun build $lxc
unset FAKE_CLONE_FULL
expect "a full clone fails verification" 1 "$rc"
has "the failure says the clone is not linked" "$case_dir/out.log" "not a linked clone"
expect "a template that failed verification is destroyed" "" "$(world_get "','.join(sorted(g))")"
expect "a template that failed verification is not promoted" "None" "$(state_get $lxc "s['current']")"
printf '#!/bin/sh\necho "$CLASS $VERSION $TEMPLATE_VMID $CLONE_VMID" > "%s/hook.out"\nexit "${HOOK_EXIT:-0}"\n' "$work" > "$work/hook-pass.sh"
printf '#!/bin/sh\nexit 1\n' > "$work/hook-fail.sh"
chmod +x "$work/hook-pass.sh" "$work/hook-fail.sh"
new_case hook-pass
config_edit "c['classes']['$lxc']['verify_hook'] = '$work/hook-pass.sh'"
build_ok $lxc "hook"
expect "the class hook receives class, version, template and clone VMID" "$lxc 1 9202 9201" "$(cat "$work/hook.out")"
new_case hook-fail
config_edit "c['classes']['$lxc']['verify_hook'] = '$work/hook-fail.sh'"
tplrun build $lxc
expect "a failing class hook fails the build" 1 "$rc"
expect "a failing class hook leaves no template and no current" "None" "$(state_get $lxc "s['current']")"
new_case hook-missing
config_edit "c['classes']['$lxc']['verify_hook'] = '$work/absent.sh'"
tplrun build $lxc
expect "a configured hook that is not an executable fails closed" 1 "$rc"

echo "== status is consumer-facing: exactly one current per class"
new_case status
build_ok $lxc "v1"; build_ok $lxc "v2"
world_edit "w['guests']['9202']['tags'] += ';current'"
tplrun status $lxc
expect "two current tags in one class: status exits 1" 1 "$rc"
has "two current tags in one class: status says so" "$case_dir/out.log" "class=$lxc ERROR current-count=2"
tplrun repair $lxc
expect "repair exits 0" 0 "$rc"
tplrun status $lxc
expect "after repair the tags follow the recorded current" "1" "$(count "^class=$lxc current=v2 vmid=9203" "$case_dir/out.log")"
world_edit "w['guests']['9203']['tags'] = 'homelab-template;lxc-runner;v2'; w['guests']['9202']['tags'] = 'homelab-template;lxc-runner;v1;current'"
tplrun status $lxc
expect "tags that disagree with the recorded state: status exits 1" 1 "$rc"
has "tags that disagree with the recorded state: status says MISMATCH" "$case_dir/out.log" "MISMATCH recorded=2"

echo "== failure marker"
new_case failure
tplrun record-failure $lxc
expect "record-failure writes the marker file" "yes" "$([ -s "$case_dir/state/failed/$lxc" ] && echo yes || echo no)"
has "record-failure prints a critical journal line" "$case_dir/out.log" "^<2>homelab-template: BUILD FAILED class=$lxc"
build_ok $lxc "success after a failure"
expect "a successful build clears the marker" "no" "$([ -e "$case_dir/state/failed/$lxc" ] && echo yes || echo no)"

echo "== pre-start read-back: one mutation per attribute, each fails a named case"
prestart_case() {
  local name="$1" cls="$2" tamper="$3" message="$4" id="$5"
  new_case "pre-$(echo "$name" | tr -c 'a-z0-9\n' '-')"
  FAKE_TAMPER="$tamper" tplrun build "$cls"
  expect "read-back case '$name': the build fails" 1 "$rc"
  has "read-back case '$name': the report names the difference" "$case_dir/out.log" "pre-start read-back differs: .*$message"
  expect "read-back case '$name': the guest is never started" 0 "$(count '^(qm|pct) start' "$case_dir/calls")"
  expect "read-back case '$name': no ok line is journaled" 0 "$(count 'READBACK ok' "$case_dir/out.log")"
  expect "read-back case '$name': the guest is destroyed" 1 "$(count "^(qm|pct) destroy $id" "$case_dir/calls")"
}
lx_net='name=eth0,bridge=VNET,firewall=1,gw=10.99.16.1,ip=10.99.16.30/24'
vm_net='virtio=AA:BB:CC:00:00:01,bridge=VNET,firewall=1'
for cls_spec in "$lxc:9202:$lx_net" "$vm:9302:$vm_net"; do
  cls="${cls_spec%%:*}"; rest="${cls_spec#*:}"; id="${rest%%:*}"; net="${rest#*:}"
  prestart_case "$cls bridge is not the guest vnet" "$cls" "{\"config_set\": {\"net0\": \"${net/VNET/vmbr0}\"}}" "net0 bridge is 'vmbr0'" "$id"
  prestart_case "$cls NIC firewall is off" "$cls" "{\"config_set\": {\"net0\": \"${net/VNET/guests},firewall=0\"}}" "net0 firewall is off" "$id"
  prestart_case "$cls second NIC on the host bridge" "$cls" "{\"config_set\": {\"net1\": \"${net/VNET/vmbr0}\"}}" "NICs are \['net0', 'net1'\]" "$id"
  for option in enable:0 policy_in:ACCEPT policy_out:ACCEPT ipfilter:0 macfilter:0 dhcp:1 radv:1 ndp:0 log_level_out:nolog; do
    prestart_case "$cls firewall option ${option%%:*} differs" "$cls" "{\"options_set\": {\"${option%%:*}\": \"${option#*:}\"}}" "firewall option ${option%%:*} is '${option#*:}'" "$id"
  done
  prestart_case "$cls option policy_out missing" "$cls" '{"options_del": ["policy_out"]}' "firewall option policy_out is 'None'" "$id"
  prestart_case "$cls extra enabled OUT ACCEPT rule" "$cls" '{"rules_add": [{"type": "out", "action": "ACCEPT", "enable": 1}]}' "firewall rules are not exactly" "$id"
  prestart_case "$cls extra disabled rule" "$cls" '{"rules_add": [{"type": "in", "action": "ACCEPT", "enable": 0}]}' "firewall rules are not exactly" "$id"
  prestart_case "$cls group rule missing" "$cls" '{"rules_drop_type": ["group"]}' "firewall rules are not exactly" "$id"
  prestart_case "$cls gateway ssh rule missing" "$cls" '{"rules_drop_type": ["in"]}' "firewall rules are not exactly" "$id"
  prestart_case "$cls ssh rule from another source" "$cls" '{"rules_modify": {"in": {"source": "10.99.16.9"}}}' "firewall rules are not exactly" "$id"
  prestart_case "$cls ssh rule with a wider port" "$cls" '{"rules_modify": {"in": {"dport": "22:100"}}}' "firewall rules are not exactly" "$id"
  prestart_case "$cls guest already in a pool" "$cls" '{"pool": "homelab"}' "guest is in pool 'homelab'" "$id"
done
prestart_case "lxc privileged" $lxc '{"config_set": {"unprivileged": "0"}}' "container is not unprivileged" 9202
prestart_case "lxc mount point" $lxc '{"config_set": {"mp0": "local-lvm:vm-1-disk-1,mp=/mnt"}}' "forbidden config key mp0" 9202
prestart_case "lxc features key" $lxc '{"config_set": {"features": "nesting=1"}}' "forbidden config key features" 9202
prestart_case "lxc raw lxc key" $lxc '{"config_set": {"lxc.cgroup2.devices.allow": "a"}}' "forbidden config key lxc.cgroup2.devices.allow" 9202
prestart_case "lxc device passthrough" $lxc '{"config_set": {"dev0": "/dev/kvm"}}' "forbidden config key dev0" 9202
prestart_case "lxc build address differs" $lxc '{"config_set": {"net0": "name=eth0,bridge=guests,firewall=1,gw=10.99.16.1,ip=10.99.16.99/24"}}' "net0 address is '10.99.16.99/24'" 9202
prestart_case "vm guest agent on" $vm '{"config_set": {"agent": "1"}}' "guest agent is not disabled" 9302
prestart_case "vm pci passthrough" $vm '{"config_set": {"hostpci0": "0000:01:00"}}' "forbidden config key hostpci0" 9302
prestart_case "vm usb passthrough" $vm '{"config_set": {"usb0": "host=1-1"}}' "forbidden config key usb0" 9302
prestart_case "vm virtiofs share" $vm '{"config_set": {"virtiofs0": "share"}}' "forbidden config key virtiofs0" 9302
prestart_case "vm raw qemu args" $vm '{"config_set": {"args": "-cpu host"}}' "forbidden config key args" 9302
prestart_case "vm serial device" $vm '{"config_set": {"serial0": "socket"}}' "forbidden config key serial0" 9302
prestart_case "vm cpu model host" $vm '{"config_set": {"cpu": "host"}}' "cpu is 'host'" 9302
prestart_case "vm cpu with nested flag" $vm '{"config_set": {"cpu": "x86-64-v2-AES,flags=+svm"}}' "cpu is 'x86-64-v2-AES,flags=+svm'" 9302
prestart_case "vm ipfilter ipset missing" $vm '{"ipset_drop": true}' "ipset ipfilter-net0 is None" 9302
prestart_case "vm ipfilter ipset has another address" $vm '{"ipset_cidrs": ["10.99.16.99"]}' "ipset ipfilter-net0 is \['10.99.16.99'\]" 9302
prestart_case "vm ssh key is not the build key" $vm '{"config_set": {"sshkeys": "ssh-ed25519%20AAAAother"}}' "sshkeys is not the ephemeral build key" 9302
prestart_case "vm ipconfig differs" $vm '{"config_set": {"ipconfig0": "ip=10.99.16.99/24,gw=10.99.16.1"}}' "ipconfig0 is" 9302

echo "== the roles assertions refuse a block that holds a reserved probe VMID"
cat > "$work/assert.yml" <<'YML'
---
- name: Evaluate the declared template classes only
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Run the role assertions only
      ansible.builtin.include_role:
        name: pve_templates
        tasks_from: assert
YML
assert_run() {
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 ANSIBLE_ROLES_PATH="$repo/iac/ansible/roles" \
    ansible-playbook "$work/assert.yml" -e "@$work/vars.json" "$@" > "$work/assert.log" 2>&1 && echo 0 || echo 1
}
expect "the shipped defaults pass the assertions" 0 "$(assert_run)"
expect "a class block holding the probe VMID 9101 fails the assertions" 1 "$(assert_run -e '{"pve_templates_classes": {"lxc-runner": {"type": "lxc", "vmid_base": 9100, "build_address": "10.99.16.30"}}}')"
expect "a build address outside the guest subnet fails the assertions" 1 "$(assert_run -e '{"pve_templates_classes": {"lxc-runner": {"type": "lxc", "vmid_base": 9200, "build_address": "10.98.16.30"}}}')"
expect "a build address equal to the gateway fails the assertions" 1 "$(assert_run -e '{"pve_templates_classes": {"lxc-runner": {"type": "lxc", "vmid_base": 9200, "build_address": "10.99.16.1"}}}')"

[ "$failures" -eq 0 ] || { echo "FAILED: $failures check(s)"; exit 1; }
echo "OK: template build framework"
