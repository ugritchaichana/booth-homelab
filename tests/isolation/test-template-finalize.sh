#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
common="${COMMON_DIR:-$repo/iac/ansible/roles/pve_templates/files/common}"
finalize="${FINALIZE_SCRIPT:-$common/finalize.sh}"
seal="$common/seal.sh"
run_script="$common/run.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$3', wanted '$2'"; failures=$((failures + 1)); fi
}
exists() { [ -e "$1" ] && echo present || echo absent; }
key_header() { printf -- '-----BEGIN %s%s-----' "$1" "PRIVATE KEY"; }
fake_aws_id() { printf '%s%s' "AKIA" "ABCDEFGHIJKLMNOP"; }
fake_gh_token() { printf '%s%s' "ghp_" "0123456789abcdefghijklmnopqrstuvwxyzAB"; }

build_id="lxc-runner-v1-20261007T000000Z-abcd1234"
rc=0
new_root() {
  root="$work/root-$1"
  rm -rf "$root"
  mkdir -p "$root/etc/ssh" "$root/root/.ssh" "$root/home/debian/.ssh" "$root/var/lib/systemd" "$root/var/lib/homelab-build" "$root/opt" "$root/srv" "$root/var/log/journal" "$root/tmp/homelab-bundle"
  echo "ssh-ed25519 AAAA build-key" > "$root/root/.ssh/authorized_keys"
  echo "ssh-ed25519 AAAA build-key" > "$root/home/debian/.ssh/authorized_keys"
  key_header "OPENSSH " > "$root/etc/ssh/ssh_host_ed25519_key"
  echo "0123456789abcdef0123456789abcdef" > "$root/etc/machine-id"
  echo "seed" > "$root/var/lib/systemd/random-seed"
  echo "journal" > "$root/var/log/journal/system.journal"
  echo '{"os": "debian 13"}' > "$root/var/lib/homelab-build/manifest.json"
}
run_finalize() {
  set +e
  FINALIZE_ROOT="$root" FINALIZE_ALLOWLIST="${ALLOWLIST:-$work/allowlist.txt}" sh "$finalize" "${1:-$build_id}" > "$root.log" 2>&1
  rc=$?
  set -e
}
: > "$work/allowlist.txt"

echo "== a clean guest passes and is cleaned, but keeps the channel open for the fetch"
new_root clean
run_finalize
expect "a clean guest exits 0" 0 "$rc"
expect "the pass marker carries the build id" "PASS $build_id" "$(cat "$root/var/lib/homelab-build/pass")"
expect "machine-id is truncated, not deleted" "present 0" "$(exists "$root/etc/machine-id") $(wc -c < "$root/etc/machine-id" | tr -d ' ')"
expect "the random seed is removed" absent "$(exists "$root/var/lib/systemd/random-seed")"
expect "the journal is emptied" 0 "$(find "$root/var/log/journal" -type f | wc -l | tr -d ' ')"
expect "the login key is still there for the two fetches" present "$(exists "$root/home/debian/.ssh/authorized_keys")"
expect "the host key is still there for the two fetches" present "$(exists "$root/etc/ssh/ssh_host_ed25519_key")"
run_finalize
expect "a second run passes again" 0 "$rc"

echo "== a planted secret means no pass marker"
plant() {
  new_root "$1"
  mkdir -p "$(dirname "$root/$2")"
  printf '%s\n' "$3" > "$root/$2"
  run_finalize
  expect "$4: finalize exits 1" 1 "$rc"
  expect "$4: no pass marker exists" absent "$(exists "$root/var/lib/homelab-build/pass")"
  expect "$4: the report names the finding" 1 "$(grep -c "$5" "$root.log")"
}
plant credentials opt/actions-runner/.credentials '{"scheme": "OAuth"}' "a planted .credentials" "forbidden file: .*/.credentials"
plant rsaparams opt/actions-runner/.credentials_rsaparams 'x' "a planted .credentials_rsaparams" "forbidden file: .*/.credentials_rsaparams"
plant runner opt/actions-runner/.runner '{"agentId": 1}' "a planted .runner" "forbidden file: .*/.runner"
plant dockercfg root/.docker/config.json '{"auths": {}}' "a docker config" "forbidden file: .*/.docker/config.json"
plant npmrc root/.npmrc '//registry/:_authToken=x' "an npmrc" "forbidden file: .*/.npmrc"
plant privkey etc/app/key.pem "$(key_header "OPENSSH ")" "a private key block" "secret pattern: /etc/app/key.pem"
plant ghtoken home/debian/notes.txt "$(fake_gh_token)" "a GitHub token" "secret pattern: /home/debian/notes.txt"
plant awskey opt/app/env "$(fake_aws_id)" "an AWS access key id" "secret pattern: /opt/app/env"

echo "== a planted secret removes a stale pass marker"
new_root stale
printf 'PASS %s\n' "$build_id" > "$root/var/lib/homelab-build/pass"
mkdir -p "$root/opt/r"; echo x > "$root/opt/r/.credentials"
run_finalize
expect "a stale pass marker does not survive a failed scan" absent "$(exists "$root/var/lib/homelab-build/pass")"

echo "== the allowlist"
new_root allowed
mkdir -p "$root/etc/app"; key_header "RSA " > "$root/etc/app/test-key.pem"
sum="$(sha256sum "$root/etc/app/test-key.pem" | cut -d' ' -f1)"
run_finalize
expect "a test key that is not allowlisted fails" 1 "$rc"
printf '%s  /etc/app/test-key.pem\n' "$sum" > "$work/allow-one.txt"
ALLOWLIST="$work/allow-one.txt" run_finalize
expect "the same file with its sha256 and path allowlisted passes" 0 "$rc"
echo "$(key_header "RSA ")changed" > "$root/etc/app/test-key.pem"
ALLOWLIST="$work/allow-one.txt" run_finalize
expect "an allowlisted path with changed content fails" 1 "$rc"

echo "== inputs"
new_root nomanifest
rm "$root/var/lib/homelab-build/manifest.json"
run_finalize
expect "no manifest means no pass marker" 1 "$rc"
expect "no manifest leaves no pass marker file" absent "$(exists "$root/var/lib/homelab-build/pass")"
new_root badid
run_finalize 'x; rm -rf /'
expect "a malformed build id is refused with exit 2" 2 "$rc"

echo "== the seal removes what the fetch needed"
run_seal() {
  set +e
  FINALIZE_ROOT="$root" sh "$seal" > "$root.seal.log" 2>&1
  rc=$?
  set -e
}
new_root seal
run_seal
expect "the seal exits 0" 0 "$rc"
expect "the seal prints SEAL-OK" 1 "$(grep -c '^SEAL-OK$' "$root.seal.log")"
expect "the seal removes the root login key" absent "$(exists "$root/root/.ssh/authorized_keys")"
expect "the seal removes the login user key" absent "$(exists "$root/home/debian/.ssh/authorized_keys")"
expect "the seal removes the host keys" absent "$(exists "$root/etc/ssh/ssh_host_ed25519_key")"
expect "the seal truncates machine-id again" "present 0" "$(exists "$root/etc/machine-id") $(wc -c < "$root/etc/machine-id" | tr -d ' ')"
expect "the seal removes the build output and the pushed bundle" "absent absent" "$(exists "$root/var/lib/homelab-build") $(exists "$root/tmp/homelab-bundle")"
new_root seal-leftover
mkdir -p "$root/home/debian/.ssh"
chmod 0500 "$root/home/debian/.ssh"
if [ "$(id -u)" -ne 0 ]; then
  run_seal
  expect "a key the seal cannot remove fails it" 1 "$rc"
  expect "a failed seal never prints SEAL-OK" 0 "$(grep -c '^SEAL-OK$' "$root.seal.log")"
  chmod 0700 "$root/home/debian/.ssh"
fi

echo "== run.sh runs Ansible inside the guest"
mkdir -p "$work/fakebin"
cat > "$work/fakebin/ansible-playbook" <<'SH'
#!/bin/sh
echo "ansible-playbook $*" >> "$FAKE_RUN_CALLS"
mkdir -p "$FINALIZE_ROOT/var/lib/homelab-build"
echo '{"os": "debian 13"}' > "$FINALIZE_ROOT/var/lib/homelab-build/manifest.json"
SH
cat > "$work/fakebin/apt-get" <<'SH'
#!/bin/sh
echo "apt-get $*" >> "$FAKE_RUN_CALLS"
SH
chmod +x "$work/fakebin/ansible-playbook" "$work/fakebin/apt-get"
mkdir -p "$work/bundle" && cp "$common"/*.sh "$common/playbook.yml" "$common/scan-allowlist.txt" "$work/bundle/"
run_in_guest() {
  set +e
  PATH="$1:$PATH" FAKE_RUN_CALLS="$work/run-calls" FINALIZE_ROOT="$root" sh "$work/bundle/run.sh" "$build_id" > "$root.run.log" 2>&1
  rc=$?
  set -e
}
new_root run
: > "$work/run-calls"
run_in_guest "$work/fakebin"
expect "run.sh finishes with the pass marker when Ansible is already present" 0 "$rc"
expect "run.sh calls ansible-playbook with -c local on localhost, inside the guest" 1 "$(grep -c '^ansible-playbook -c local -i localhost, .*/playbook.yml -e build_id=' "$work/run-calls")"
expect "run.sh does not install or purge Ansible when it was already there" 0 "$(grep -c '^apt-get' "$work/run-calls")"
expect "run.sh ends with the pass marker" "PASS $build_id" "$(cat "$root/var/lib/homelab-build/pass")"
new_root run-install
: > "$work/run-calls"
mkdir -p "$work/emptybin"
for tool_name in sh dirname mkdir cat cp rm sed grep find mktemp sha256sum cut sync printf echo head tr true; do
  found="$(command -v "$tool_name" || true)"
  case "$found" in /*) ln -sf "$found" "$work/emptybin/$tool_name" ;; esac
done
cat > "$work/emptybin/apt-get" <<'SH'
#!/bin/sh
echo "apt-get $*" >> "$FAKE_RUN_CALLS"
case "$*" in *"install"*) cp "$FAKE_ANSIBLE" "$(dirname "$0")/ansible-playbook" ;; esac
SH
chmod +x "$work/emptybin/apt-get"
FAKE_ANSIBLE="$work/fakebin/ansible-playbook" PATH="$work/emptybin" FAKE_RUN_CALLS="$work/run-calls" FINALIZE_ROOT="$root" sh "$work/bundle/run.sh" "$build_id" > "$root.run.log" 2>&1 && rc=0 || rc=$?
expect "run.sh installs Ansible when the guest has none and still finishes" 0 "$rc"
expect "run.sh installs ansible-core" 1 "$(grep -c '^apt-get install .*ansible-core' "$work/run-calls")"
expect "run.sh purges the Ansible it installed before the scan" 1 "$(grep -c '^apt-get purge .*ansible-core' "$work/run-calls")"

echo "== the shipped scripts parse and the shipped playbook passes a syntax check"
for script in run.sh finalize.sh seal.sh; do
  expect "$script parses" 0 "$(sh -n "$common/$script" && echo 0 || echo 1)"
done
if command -v ansible-playbook >/dev/null 2>&1; then
  expect "the shipped playbook passes ansible-playbook --syntax-check" 0 "$(ANSIBLE_LOCALHOST_WARNING=False ansible-playbook --syntax-check -i localhost, "$common/playbook.yml" -e build_id=x > "$work/syntax.log" 2>&1 && echo 0 || echo 1)"
  ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -c local -i localhost, "$common/playbook.yml" -e build_id=probe-build -e "manifest_path=$work/manifest-out.json" > "$work/play.log" 2>&1 \
    || { cat "$work/play.log"; echo "FAIL the shipped playbook did not run on this machine"; failures=$((failures + 1)); }
  expect "the playbook writes a manifest with the build id, the OS, the kernel and the package versions" "probe-build yes yes yes" "$(python3 -I - "$work/manifest-out.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(m["build_id"], "yes" if m["os_release"].strip() else "no", "yes" if m["kernel"] else "no", "yes" if m["packages"] and all(isinstance(v, str) and v for v in m["packages"].values()) else "no")
PY
)"
else
  echo "FAIL ansible-playbook is not installed, the playbook syntax check did not run"
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] || { echo "FAILED: $failures check(s)"; exit 1; }
echo "OK: template finalize"
