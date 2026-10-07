#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundle="${BUNDLE_DIR:-$repo/iac/ansible/roles/pve_templates/files/bundles/vm-docker}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$3', wanted '$2'"; failures=$((failures + 1)); fi
}

syntax() { ANSIBLE_LOCALHOST_WARNING=False ansible-playbook --syntax-check -i localhost, "$1/playbook.yml" >/dev/null 2>&1 && echo ok || echo bad; }

daemon_check() {
  python3 -I - "$1/daemon.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = [k for k in ("hosts", "insecure-registries", "tls", "tlsverify") if k in d]
print("bad:" + ",".join(bad) if bad else "ok")
PY
}

versions_check() {
  python3 -I - "$1/versions.yml" <<'PY'
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
bad = []
for p in d["apt_packages"]:
    if not p.get("name") or not re.search(r"\d", str(p.get("version", ""))) or str(p["version"]) == "latest":
        bad.append(str(p.get("name")))
for a in d["downloads"]:
    if not (a.get("version") and a.get("url", "").startswith("https://") and a["version"] in a["url"] and re.fullmatch(r"[0-9a-f]{64}", a.get("sha256", ""))):
        bad.append(a.get("name", "?"))
print("incomplete:" + ",".join(bad) if bad else "ok")
PY
}

expect "class playbook passes the syntax check" ok "$(syntax "$bundle")"
expect "daemon.json has no tcp host or insecure registry" ok "$(daemon_check "$bundle")"
expect "versions.yml entries are complete" ok "$(versions_check "$bundle")"

mutant="$work/mutant"
cp -r "$bundle" "$mutant"
python3 -I - "$mutant/daemon.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hosts"] = ["tcp://0.0.0.0:2375"]
json.dump(d, open(p, "w"))
PY
expect "mutation: a tcp host in daemon.json is rejected" "bad:hosts" "$(daemon_check "$mutant")"
cp "$bundle/daemon.json" "$mutant/daemon.json"
sed -i 's/[0-9a-f]\{64\}/0/' "$mutant/versions.yml"
expect "mutation: a short hash in versions.yml is rejected" "incomplete:actions-runner" "$(versions_check "$mutant")"

if [ "$failures" -ne 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "all passed"
