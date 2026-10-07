#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
step="${GUEST_STEP:-$repo/iac/ansible/roles/pve_templates/files/homelab-template-guest.py}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat > "$work/bin/ssh" <<'PY'
#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
open(os.environ["FAKE_SSH_CALLS"], "a", encoding="utf-8").write(" ".join(args) + "\n")
remote = args[-1]
if remote == "true":
    marker = os.environ["FAKE_SSH_CALLS"] + ".up"
    if os.environ.get("FAKE_SSH_DOWN_ONCE") and not os.path.exists(marker):
        open(marker, "w").close()
        sys.exit(255)
    sys.exit(0)
if remote.startswith("rm -rf /tmp/homelab-bundle"):
    open(os.environ["FAKE_SSH_CALLS"] + ".bundle", "wb").write(sys.stdin.buffer.read())
    sys.exit(0)
if "/run.sh " in remote:
    sys.exit(int(os.environ.get("FAKE_RUN_RC", "0")))
if "/seal.sh" in remote:
    sys.stdout.write(os.environ.get("FAKE_SEAL", "SEAL-OK\n"))
    sys.exit(int(os.environ.get("FAKE_SEAL_RC", "0")))
if remote.endswith("/pass"):
    sys.stdout.write(os.environ.get("FAKE_PASS", ""))
    sys.exit(0)
if remote.endswith("/manifest.json"):
    limit = int(remote.split("head -c ")[1].split()[0])
    sys.stdout.buffer.write(open(os.environ["FAKE_MANIFEST_FILE"], "rb").read()[:limit])
    sys.exit(0)
sys.exit(3)
PY
chmod +x "$work/bin/ssh"
export PATH="$work/bin:$PATH" FAKE_SSH_CALLS="$work/ssh-calls"

failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$3', wanted '$2'"; failures=$((failures + 1)); fi
}

new_case() {
  case_dir="$work/$1"
  rm -rf "$case_dir"
  mkdir -p "$case_dir/work/build/out" "$case_dir/work/build/bundle"
  : > "$FAKE_SSH_CALLS"
  rm -f "$FAKE_SSH_CALLS.up" "$FAKE_SSH_CALLS.bundle"
  echo "tool" > "$case_dir/work/build/bundle/run.sh"
  : > "$case_dir/work/build/key"; : > "$case_dir/work/build/key.pub"; : > "$case_dir/work/build/known_hosts"
  cat > "$case_dir/work/build/params.env" <<ENV
BUILD_ID=lxc-runner-v1-20261007T000000Z-abcd1234
CLASS=lxc-runner
VERSION=1
ADDRESS=${ADDRESS:-10.99.16.30}
LOGIN_USER=${LOGIN_USER:-root}
USE_SUDO=${USE_SUDO:-0}
KEY=$case_dir/work/build/key
KNOWN_HOSTS=$case_dir/work/build/known_hosts
BUNDLE=$case_dir/work/build/bundle
OUT=$case_dir/work/build/out
PREVIOUS_MANIFEST=${PREVIOUS_MANIFEST:-}
MANIFEST_MAX_BYTES=1000
SSH_WAIT_SECONDS=20
RUN_SECONDS=30
ENV
  printf '{"os": "debian 13", "dotnet": "8.0.100", "node": "22.1.0"}\n' > "$case_dir/manifest.json"
  export FAKE_MANIFEST_FILE="$case_dir/manifest.json" FAKE_PASS="PASS lxc-runner-v1-20261007T000000Z-abcd1234"
}
rc=0
step_run() {
  set +e
  python3 -I "$step" "$@" --work-dir "$case_dir/work" > "$case_dir/out.log" 2>&1
  rc=$?
  set -e
}
count() { grep -cE -- "$1" "$2" || true; }
exists() { [ -e "$1" ] && echo present || echo absent; }

echo "== ssh options on every connection"
new_case happy
step_run build
expect "a good build exits 0" 0 "$rc"
expect "the manifest is written as fetched" "$(cat "$case_dir/manifest.json")" "$(cat "$case_dir/work/build/out/manifest.json")"
expect "the pass marker carries the build id" "PASS lxc-runner-v1-20261007T000000Z-abcd1234" "$(cat "$case_dir/work/build/out/pass")"
expect "the bundle was pushed as a tar stream" "yes" "$([ -s "$FAKE_SSH_CALLS.bundle" ] && echo yes || echo no)"
total="$(wc -l < "$FAKE_SSH_CALLS" | tr -d ' ')"
for option in "BatchMode=yes" "IdentitiesOnly=yes" "ForwardAgent=no" "ForwardX11=no" "ClearAllForwardings=yes" "PermitLocalCommand=no" "UserKnownHostsFile=$case_dir/work/build/known_hosts" "GlobalKnownHostsFile=/dev/null" "-F /dev/null"; do
  expect "every ssh connection sets $option" "$total" "$(grep -cF -- "$option" "$FAKE_SSH_CALLS")"
done
expect "no connection carries a sudo prefix for a root login" 0 "$(count 'sudo' "$FAKE_SSH_CALLS")"

USE_SUDO=1 LOGIN_USER=debian new_case sudo
step_run build
expect "a sudo login prefixes the run, pass, manifest and seal commands" 4 "$(count 'sudo -n (sh /tmp/homelab-bundle/(run|seal).sh|head -c)' "$FAKE_SSH_CALLS")"

echo "== the seal is the last connection and gates the pass marker"
new_case seal-order
step_run build
fetch_last="$(grep -n 'head -c' "$FAKE_SSH_CALLS" | tail -1 | cut -d: -f1)"
seal_line="$(grep -n 'seal.sh' "$FAKE_SSH_CALLS" | cut -d: -f1)"
expect "both fetches happen before the seal" "yes" "$([ "$fetch_last" -lt "$seal_line" ] && echo yes || echo no)"
expect "the seal is the last connection" "$(wc -l < "$FAKE_SSH_CALLS" | tr -d ' ')" "$seal_line"
new_case seal-fails
FAKE_SEAL='SEAL-FAILED: key material left' FAKE_SEAL_RC=1 step_run build
expect "a failed seal fails the step" 1 "$rc"
expect "a failed seal writes no pass marker" absent "$(exists "$case_dir/work/build/out/pass")"
new_case seal-silent
FAKE_SEAL='' step_run build
expect "a seal that never says SEAL-OK fails the step" 1 "$rc"
expect "a seal that never says SEAL-OK writes no pass marker" absent "$(exists "$case_dir/work/build/out/pass")"
new_case seal-closed
FAKE_SEAL_RC=255 step_run build
expect "a connection that closes after SEAL-OK is a success" 0 "$rc"
expect "a connection that closes after SEAL-OK writes the pass marker" present "$(exists "$case_dir/work/build/out/pass")"

echo "== no pass marker without a good in-guest result"
new_case rc-fails
FAKE_RUN_RC=1 step_run build
expect "an in-guest failure (scan failed) fails the step" 1 "$rc"
expect "an in-guest failure writes no pass marker" absent "$(exists "$case_dir/work/build/out/pass")"
new_case wrong-id
FAKE_PASS="PASS some-other-build" step_run build
expect "a marker for another build id fails the step" 1 "$rc"
expect "a marker for another build id writes no pass marker" absent "$(exists "$case_dir/work/build/out/pass")"
new_case empty-pass
FAKE_PASS="" step_run build
expect "an empty marker fails the step" 1 "$rc"
pad() { printf '{"pad": "%s"}' "$(head -c "$1" /dev/zero | tr '\0' 'x')"; }
new_case big-manifest
pad 990 > "$case_dir/manifest.json"
step_run build
expect "a valid manifest of one byte above the 1000 byte cap fails the step" 1 "$rc"
expect "a valid manifest of one byte above the cap writes no pass marker" absent "$(exists "$case_dir/work/build/out/pass")"
new_case manifest-at-cap
pad 989 > "$case_dir/manifest.json"
step_run build
expect "a valid manifest of exactly the 1000 byte cap is accepted" 0 "$rc"
new_case not-json
printf 'not json' > "$case_dir/manifest.json"
step_run build
expect "a manifest that is not JSON fails the step" 1 "$rc"
new_case json-array
printf '[1, 2]' > "$case_dir/manifest.json"
step_run build
expect "a manifest that is not a JSON object fails the step" 1 "$rc"

echo "== parameters are validated before any connection"
ADDRESS='10.99.16.30; id' new_case bad-address
step_run build
expect "a malformed address is refused" 1 "$rc"
expect "a malformed address opens no connection" 0 "$(wc -l < "$FAKE_SSH_CALLS" | tr -d ' ')"

echo "== waiting for sshd"
new_case ssh-late
FAKE_SSH_DOWN_ONCE=1 step_run build
expect "a guest whose sshd answers on the second try still builds" 0 "$rc"

echo "== the manifest diff goes to the step output"
PREVIOUS_MANIFEST="$work/diff/previous.json" new_case diff
printf '{"os": "debian 13", "dotnet": "8.0.100", "node": "22.1.0\\u001b[31m", "added": "x"}\n' > "$case_dir/manifest.json"
printf '{"os": "debian 13", "dotnet": "8.0.100", "node": "22.0.0", "gone": "1"}\n' > "$case_dir/previous.json"
step_run build
expect "the diff reports three changed entries" 1 "$(count 'MANIFEST-DIFF 3 changed entries' "$case_dir/out.log")"
expect "a changed entry shows old and new value" 1 "$(count 'MANIFEST-DIFF node: 22.0.0 -> 22.1.0\?\[31m' "$case_dir/out.log")"
expect "an added entry is shown" 1 "$(count 'MANIFEST-DIFF added: \(absent\) -> x' "$case_dir/out.log")"
expect "a removed entry is shown" 1 "$(count 'MANIFEST-DIFF gone: 1 -> \(absent\)' "$case_dir/out.log")"
expect "control characters never reach the output" 0 "$(grep -c "$(printf '\033')" "$case_dir/out.log" || true)"
new_case first
step_run build
expect "the first version says every entry is new" 1 "$(count 'MANIFEST-DIFF no previous version' "$case_dir/out.log")"

echo "== cleanup removes the key material"
new_case cleanup
step_run cleanup
expect "cleanup removes the private key" absent "$(exists "$case_dir/work/build/key")"
expect "cleanup removes the public key" absent "$(exists "$case_dir/work/build/key.pub")"
expect "cleanup removes the known_hosts file" absent "$(exists "$case_dir/work/build/known_hosts")"
rm -rf "$case_dir/work/build"
step_run cleanup
expect "cleanup with no work directory is not an error" 0 "$rc"

[ "$failures" -eq 0 ] || { echo "FAILED: $failures check(s)"; exit 1; }
echo "OK: template guest step"
