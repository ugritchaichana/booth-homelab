#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
role="${SIM_CACHE_ROLE_DIR:-$repo/iac/ansible/roles/sim_cache_service}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ansible >/dev/null || { echo "ERROR: ansible is not installed" >&2; exit 2; }
[ -f "$role/templates/store.service.j2" ] || { echo "ERROR: no unit template under $role" >&2; exit 2; }

cat > "$work/vars.json" <<'JSON'
{"cache_endpoint": {"address": "10.99.17.10", "port": 8080}, "sim_cache_endpoint": {"address": "10.99.17.11"},
 "sim_cache_secrets": {"reader_secret": "sentinel-reader-secret-never-in-a-unit-0123456789", "writer_secret": "sentinel-writer-secret-never-in-a-unit-0123456789",
                       "tailscale_auth_key": "sentinel-auth-key-never-in-a-unit-0123456789",
                       "reader_key_id": "SENTINELREADERKEYID0123456789", "writer_key_id": "SENTINELWRITERKEYID0123456789"}}
JSON

cat > "$work/check.py" <<'PY'
import hashlib
import http.client
import importlib.util
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import yaml

role, out, work = sys.argv[1:4]
READID, WRITEID = "SENTINELREADERKEYID0123456789", "SENTINELWRITERKEYID0123456789"
READER, WRITER, AUTHKEY = ("sentinel-reader-secret-never-in-a-unit-0123456789", "sentinel-writer-secret-never-in-a-unit-0123456789", "sentinel-auth-key-never-in-a-unit-0123456789")
errors = []
defaults = yaml.safe_load(open(f"{role}/defaults/main.yml", encoding="utf-8"))
tasks = yaml.safe_load(open(f"{role}/tasks/main.yml", encoding="utf-8"))


def read(name):
    text = open(f"{out}/{name}", encoding="utf-8").read()
    if "{{" in text:
        errors.append(f"{name}: unrendered expression")
    if name not in ("s3.json", "allowed-keys"):
        for secret in (READER, WRITER, AUTHKEY, READID, WRITEID):
            if secret in text:
                errors.append(f"{name}: a secret value reached the unit")
    return text, [raw.strip() for raw in text.splitlines()]


def need(name, lines, wanted):
    for line in wanted:
        if line not in lines:
            errors.append(f"{name} lacks the line {line!r}")


HARDENING = ["NoNewPrivileges=true", "ProtectSystem=strict", "PrivateTmp=true", "ProtectHome=true", "ProtectKernelTunables=yes", "ProtectKernelModules=yes", "ProtectControlGroups=yes", "LockPersonality=yes"]

text, lines = read("sim-cache-store.service")
need("store", lines, HARDENING + ["CapabilityBoundingSet=", "PrivateDevices=yes", "SystemCallFilter=@system-service", "User=sim-store", "WorkingDirectory=/var/lib/sim-cache", "ReadWritePaths=/var/lib/sim-cache"])
exec_start = next((x for x in lines if x.startswith("ExecStart=")), "")
flags = exec_start.split()
for flag in ("server", "-ip=127.0.0.1", "-ip.bind=127.0.0.1", "-dir=/var/lib/sim-cache/data", "-master.telemetry=false", "-filer", "-s3", "-s3.config=/etc/sim-cache/s3.json",
             "-s3.iam=false", "-s3.autoCreateBucket=false", "-filer.tusBasePath=", "-s3.port.iceberg=0", "-s3.port.lance=0", "-s3.port=8333", "-filer.port=8888", "-master.port=9333", "-volume.port=8082"):
    if flag not in flags:
        errors.append(f"the store ExecStart lacks {flag!r}: {exec_start}")
for forbidden in ("0.0.0.0", "-s3.ip.bind", "-webdav", "-sftp", "-mq", "-metricsPort"):
    if forbidden in exec_start:
        errors.append(f"the store ExecStart must not contain {forbidden!r}")
ports = [int(x) for x in re.findall(r"-(?:master|volume|filer|s3)\.port=(\d+)", exec_start)]
if 8080 in ports or len(set(ports)) != len(ports):
    errors.append(f"the store ports must be distinct and leave the cache port to the proxy: {ports}")

text, lines = read("sim-cache-tripwire.service")
need("tripwire", lines, HARDENING + ["User=sim-proxy", "Restart=no", "OnFailure=sim-cache-trip-failure.service"])
exec_start = next((x for x in lines if x.startswith("ExecStart=")), "")
for part in ("/usr/bin/python3 -I ", "--listen 0.0.0.0:8080", "--upstream 127.0.0.1:8333", "--allowed-file /etc/sim-cache/allowed-keys", "--state-dir /var/lib/sim-cache/state", "--log-file /var/log/sim-cache/audit.jsonl"):
    if part not in exec_start:
        errors.append(f"the tripwire ExecStart lacks {part!r}")
if "--allowed " in exec_start or "KEYID" in exec_start:
    errors.append("the key ids must come from the allowed-keys file, never from the unit")
rw = next((x for x in lines if x.startswith("ReadWritePaths=")), "")
if "/var/lib/sim-cache/state/tripwire" not in rw or "/var/log/sim-cache" not in rw or "/var/lib/sim-cache/data" in rw:
    errors.append("the tripwire may write only its marker directory and its log: " + rw)

text, lines = read("tailscaled.service")
need("tailscaled", lines, HARDENING + ["BindsTo=sim-cache-tripwire.service", "After=network-online.target sim-cache-tripwire.service", "ConditionPathExists=!/var/lib/sim-cache/state/tripwire/tripped"])
if any(x.startswith("Requires=") for x in lines):
    errors.append("the connector must be bound to the proxy, not merely require it: a crashed proxy would leave it running")
exec_start = next((x for x in lines if x.startswith("ExecStart=")), "")
if "--tun=userspace-networking" not in exec_start:
    errors.append("the connector must run in userspace networking: no tun device, no kernel route")
for word in ("socks5", "outbound-http-proxy", "advertise-routes", "advertise-exit-node", "--ssh", "authkey", "auth-key"):
    if word in text:
        errors.append(f"tailscaled must not contain {word!r}")

text, lines = read("sim-cache-trip.service")
need("trip", lines, ["ConditionPathExists=/var/lib/sim-cache/state/tripwire/tripped", "Type=oneshot", "ExecStart=/usr/bin/systemctl stop tailscaled.service"] + HARDENING[:2])
curl = [x for x in lines if x.startswith("ExecStart=-/usr/bin/curl")]
if len(curl) != 1 or "-X PUT" not in curl[0] or "@/var/lib/sim-cache/state/tripwire/tripped" not in curl[0] or "http://127.0.0.1:8888/buckets/sim-control/tripwire" not in curl[0]:
    errors.append("the trip service must publish the marker to the control bucket through the loopback filer: " + str(curl))
stop = "ExecStart=/usr/bin/systemctl stop tailscaled.service"
if curl and stop in lines and lines.index(stop) > lines.index(curl[0]):
    errors.append("the connector must be stopped before the marker is published")

text, lines = read("sim-cache-trip.path")
need("trip.path", lines, ["PathChanged=/var/lib/sim-cache/state/tripwire", "Unit=sim-cache-trip.service"])
if "PathExists" in text:
    errors.append("the trip path must not use PathExists: it would retrigger while the marker stays")

text, lines = read("sim-cache-trip-failure.service")
need("trip-failure", lines, ["Type=oneshot", "ExecStart=/usr/bin/touch /var/lib/sim-cache/state/tripwire/tripped", "ReadWritePaths=/var/lib/sim-cache/state/tripwire"] + HARDENING[:2])

keys_text, keys_lines = read("allowed-keys")
if keys_lines != [f"sim-read:{READID}", f"sim-write:{WRITEID}"]:
    errors.append("allowed-keys must hold one name:keyid line per identity: %r" % keys_lines)
if any(secret in keys_text for secret in (READER, WRITER, AUTHKEY)):
    errors.append("allowed-keys must not hold a secret key")

# identity semantics, modelled on weed/s3api/auth_credentials.go (Identity.CanDo and the anonymous branch of the auth switch), release 4.48
doc = json.loads(open(f"{out}/s3.json", encoding="utf-8").read())
if set(doc) != {"identities"}:
    errors.append("s3.json must hold exactly the key identities (a misspelt key leaves the gateway with no identity): %r" % sorted(doc))
idents = {i["name"]: i for i in doc.get("identities", [])}
if sorted(idents) != ["sim-read", "sim-write"]:
    errors.append("s3.json must hold exactly sim-read and sim-write, and no identity named anonymous: %r" % sorted(idents))


def can_do(identity, action, bucket):
    for granted in identity["actions"]:
        if granted == action:
            return True
        if "*" not in granted and "?" not in granted and granted in (f"{action}:{bucket}", f"Admin:{bucket}"):
            return True
    return False


want = {
    "sim-read": {("Read", "sim-cache"): True, ("List", "sim-cache"): True, ("Write", "sim-cache"): False, ("Read", "sim-control"): True, ("List", "sim-control"): True,
                 ("Write", "sim-control"): False, ("Read", "other"): False, ("Write", "other"): False, ("Admin", "sim-cache"): False},
    "sim-write": {("Read", "sim-cache"): True, ("List", "sim-cache"): True, ("Write", "sim-cache"): True, ("Read", "sim-control"): True, ("List", "sim-control"): True,
                  ("Write", "sim-control"): False, ("Read", "other"): False, ("Write", "other"): False, ("Admin", "sim-cache"): False},
}
for name, matrix in want.items():
    ident = idents.get(name)
    if not ident:
        continue
    if [c["accessKey"] for c in ident["credentials"]] != [{"sim-read": READID, "sim-write": WRITEID}[name]]:
        errors.append(f"{name} must have one credential whose access key is the random key id, never its public name")
    for (action, bucket), allowed_ in matrix.items():
        if can_do(ident, action, bucket) != allowed_:
            errors.append(f"{name} {action} on {bucket} should be {'allowed' if allowed_ else 'refused'}: {ident['actions']}")
    for granted in ident["actions"]:
        if ":" not in granted or "*" in granted or "?" in granted or granted.startswith("Admin"):
            errors.append(f"{name} holds {granted!r}: every action must name one bucket, with no wildcard and no admin")
secrets = {n: i["credentials"][0]["secretKey"] for n, i in idents.items() if i.get("credentials")}
if secrets != {"sim-read": READER, "sim-write": WRITER}:
    errors.append("s3.json must carry each identity's own secret")


def walk(items):
    for task in items:
        yield task
        for key in ("block", "rescue", "always"):
            if key in task:
                yield from walk(task[key])


inherit = {}


def effective_no_log(items, parent=False):
    for task in items:
        value = task.get("no_log", parent)
        inherit[id(task)] = value is True
        for key in ("block", "rescue", "always"):
            if key in task:
                effective_no_log(task[key], value)


effective_no_log(tasks)
downloads = joins = 0
for task in walk(tasks):
    if "block" in task:
        continue
    dumped = json.dumps(task)
    name = task.get("name", "?")
    if "sim_cache_secrets" in dumped and not inherit[id(task)]:
        errors.append(f"task {name!r} reads a secret without no_log: true")
    for module in ("ansible.builtin.command", "ansible.builtin.shell"):
        if module in task:
            args = task[module]
            argv = " ".join(str(a) for a in (args.get("argv") or [args.get("cmd", "")] if isinstance(args, dict) else [args]))
            if "sim_cache_secrets" in argv or "_secret" in argv:
                errors.append(f"task {name!r} puts a secret on argv")
            if module == "ansible.builtin.shell":
                errors.append(f"task {name!r} uses a shell")
            if "up" in (args.get("argv") or []):
                joins += 1
                if "--auth-key=file:{{ sim_cache_service_tailscale_authkey_file }}" not in args["argv"]:
                    errors.append("tailscale up must read the auth key from the file, never from argv")
                if "--advertise-tags={{ sim_cache_service_tailscale_tag }}" not in args["argv"]:
                    errors.append("tailscale up must advertise the cache tag")
    if "ansible.builtin.get_url" in task:
        downloads += 1
        if not str(task["ansible.builtin.get_url"].get("checksum", "")).startswith("sha256:{{ sim_cache_service_"):
            errors.append(f"download {name!r} is not pinned by a role sha256")
if downloads != 2 or joins != 1:
    errors.append(f"expected 2 pinned downloads and 1 tailnet join, found {downloads} and {joins}")
for src, group in (("s3.json.j2", "{{ sim_cache_service_group }}"), ("allowed-keys.j2", "{{ sim_cache_service_proxy_group }}")):
    writers = [t for t in tasks if t.get("ansible.builtin.template", {}).get("src") == src]
    if len(writers) != 1 or writers[0].get("no_log") is not True:
        errors.append(f"the task that writes {src} must exist once and carry no_log: true")
    elif writers[0]["ansible.builtin.template"].get("mode") != "0640" or writers[0]["ansible.builtin.template"].get("group") != group or writers[0]["ansible.builtin.template"].get("owner") != "root":
        errors.append(f"{src} must be written root:{group} mode 0640")
always = [t for t in walk(tasks) if "always" in t]
if not any(x.get("ansible.builtin.file", {}).get("state") == "absent" and "authkey" in x["ansible.builtin.file"]["path"] for t in always for x in t["always"]):
    errors.append("the auth key file must be removed in an always block")
want_defaults = {
    "sim_cache_service_seaweed_version": "4.48",
    "sim_cache_service_seaweed_sha256": "4a7d108384d044d95212d1342cdda9533fa55842c1c9b41f606ca3c8a9561124",
    "sim_cache_service_tailscale_sha256": "512f613ed7d04fc7282f7dc5bd76aa105aae28168fbb9357eb749ebcbc29f0ae",
    "sim_cache_service_tailscale_tag": "tag:lab-cache",
    "sim_cache_service_listen_port": "{{ cache_endpoint.port }}",
}
for key, value in want_defaults.items():
    if defaults.get(key) != value:
        errors.append(f"{key} is {defaults.get(key)!r}, want {value!r}")

# the proxy: behaviour against a fake upstream
spec = importlib.util.spec_from_file_location("tripwire", f"{role}/files/tripwire.py")
tripwire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tripwire)
allowed = {READID: "sim-read", WRITEID: "sim-write"}
auth = lambda key: {"Authorization": f"AWS4-HMAC-SHA256 Credential={key}/20261021/us-east-1/s3/aws4_request, SignedHeaders=host, Signature=0"}
import email.message
twice = email.message.Message()
twice["Authorization"] = auth(READID)["Authorization"]
twice["Authorization"] = auth(READID)["Authorization"]
for headers, query, trips in [
    (auth(READID), {}, False), (auth(WRITEID), {}, False), ({}, {}, True), (auth("nobody"), {}, True), (auth(READID + "x"), {}, True),
    (auth("sim-read"), {}, True), ({"Authorization": f"AWS {READID}:abc"}, {}, True), (auth(READID), {"X-Amz-Credential": [READID + "/x"]}, True), ({}, {"X-Amz-Signature": ["0"]}, True),
    (twice, {}, True),
]:
    if bool(tripwire.violation(headers, query, allowed)) != trips:
        errors.append("violation(%r, %r) should %s" % (headers, query, "trip" if trips else "not trip"))


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for(predicate, seconds=5):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


seen = []


class Upstream(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, status, body=b"", length=True):
        self.send_response(status)
        if length:
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def handle_any(self):
        size = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(size) if size else b""
        seen.append((self.command, self.path, self.headers.get("Host"), self.headers.get("Authorization"), hashlib.sha256(body).hexdigest()))
        if self.path.startswith("/denied"):
            return self.reply(403, b"<Error><Code>AccessDenied</Code></Error>")
        if self.path.startswith("/badkey"):
            return self.reply(403, b"<Error><Code>InvalidAccessKeyId</Code></Error>")
        if self.path.startswith("/stream"):
            return self.reply(200, b"s" * 1000, length=False)
        self.reply(200, b"object-body" if self.command != "PUT" else b"")

    do_GET = do_PUT = do_HEAD = do_POST = do_DELETE = handle_any


with tempfile.TemporaryDirectory() as tmp:
    upstream = HTTPServer(("127.0.0.1", 0), Upstream)
    threading.Thread(target=upstream.serve_forever, daemon=True).start()
    state, log = f"{tmp}/state", f"{tmp}/log/audit.jsonl"
    marker = f"{state}/tripwire/tripped"
    os.makedirs(os.path.dirname(marker))
    port = free_port()
    keyfile = f"{tmp}/allowed-keys"
    open(keyfile, "w", encoding="utf-8").write(f"sim-read:{READID}\nsim-write:{WRITEID}\n")
    argv = [sys.executable, "-I", f"{role}/files/tripwire.py", "--listen", f"127.0.0.1:{port}", "--upstream", f"127.0.0.1:{upstream.server_address[1]}",
            "--state-dir", state, "--log-file", log, "--allowed-file", keyfile]
    proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL)

    def call(method, path, headers=None, body=None, raw=False):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        conn.request(method, path, body=body, headers=headers or {}, encode_chunked=raw)
        resp = conn.getresponse()
        data = resp.read()
        conn.close()
        return resp.status, data

    def call_two_authorizations(path, header):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        conn.putrequest("GET", path)
        conn.putheader("Authorization", header)
        conn.putheader("Authorization", header)
        conn.endheaders()
        resp = conn.getresponse()
        data = resp.read()
        conn.close()
        return resp.status, data

    def tripped():
        return os.path.exists(marker)

    def reset():
        if os.path.exists(marker):
            os.remove(marker)
        del seen[:]

    try:
        if not wait_for(lambda: socket.socket().connect_ex(("127.0.0.1", port)) == 0):
            errors.append("the proxy did not listen")
        good = {**auth(READID), "Host": "10.99.17.11:8080"}
        status, data = call("GET", "/sim-cache/obj", good)
        if (status, data) != (200, b"object-body") or tripped():
            errors.append(f"a known key must pass through untouched: {status} {data!r}")
        if not seen or seen[0][2] != "10.99.17.11:8080" or seen[0][3] != good["Authorization"]:
            errors.append("the Host and Authorization headers must reach the store unchanged (the signature covers them): %r" % (seen[:1],))
        blob = os.urandom(3 << 20)
        status, _ = call("PUT", "/sim-cache/big", {**auth(WRITEID), "Content-Length": str(len(blob))}, blob)
        if status != 200 or seen[-1][4] != hashlib.sha256(blob).hexdigest():
            errors.append("a 3 MiB upload must arrive byte for byte")
        status, data = call("HEAD", "/sim-cache/obj", good)
        if status != 200 or data:
            errors.append("HEAD must return the status and no body")
        status, data = call("GET", "/stream", good)
        if status != 200 or data != b"s" * 1000:
            errors.append("a response without a length must be streamed to its end")
        status, _ = call("PUT", "/denied", {**auth(READID), "Content-Length": "1"}, b"x")
        if status != 403 or tripped():
            errors.append("an authorised denial from the store is not an attack and must not trip the wire")
        reset()
        for label, method, path, headers in [
            ("anonymous", "GET", "/sim-cache/", {}),
            ("unknown key", "GET", "/sim-cache/", auth("nobody")),
            ("the old literal key id with a wrong signature", "GET", "/sim-cache/obj", auth("sim-read")),
            ("the old literal writer key id with a wrong signature", "PUT", "/sim-cache/obj", auth("sim-write")),
            ("query credential", "GET", "/sim-cache/obj?X-Amz-Credential=x%2Fy&X-Amz-Signature=0", auth(READID)),
            ("unsupported scheme", "GET", "/sim-cache/", {"Authorization": f"AWS {READID}:abc"}),
        ]:
            status, data = call(method, path, headers)
            if status != 403 or b"AccessDenied" not in data or seen or not tripped():
                errors.append(f"{label}: expected 403, no forward and a marker, got {status} seen={seen} tripped={tripped()}")
            reset()
        status, _ = call_two_authorizations("/sim-cache/obj", auth(READID)["Authorization"])
        if status != 403 or seen or not tripped():
            errors.append(f"two Authorization headers: expected 403, no forward and a marker, got {status} seen={seen} tripped={tripped()}")
        reset()
        status, _ = call("HEAD", "/denied", good)
        if status != 403 or not tripped():
            errors.append("a 403 to a HEAD must trip the wire after the fact: its body is empty, so the reply cannot be read")
        reset()
        status, _ = call("GET", "/badkey", good)
        if status != 403 or not tripped():
            errors.append("a credential rejection by the store must trip the wire after the fact")
        reset()
        status, _ = call("PUT", "/sim-cache/x", {**auth(WRITEID), "Transfer-Encoding": "chunked"}, iter([b"abc"]), raw=True)
        if status != 411 or seen:
            errors.append("a request without a content length must be refused with 411")
        call("GET", "/sim-cache/", {"Authorization": f"AWS4-HMAC-SHA256 Credential={READID}/20261021/us-east-1/s3/aws4_request, SignedHeaders=host, Signature=deadbeefsignature"})
        call("GET", "/sim-cache/", {})
        raw_log = open(log, encoding="utf-8").read()
        entries = [json.loads(x) for x in raw_log.splitlines()]
        if "deadbeefsignature" in raw_log or "X-Amz-Signature" in raw_log:
            errors.append("the audit log must not hold a signature")
        if READID in raw_log or WRITEID in raw_log:
            errors.append("the audit log must name the identity, never the key id")
        if not entries or not all({"time", "remote", "method", "path", "status", "identity"} <= set(e) for e in entries) or not any(e.get("tripped") for e in entries):
            errors.append("every request must land in the audit log with its outcome")
        body = open(marker, encoding="utf-8").read() if tripped() else ""
        if "anonymous request" not in body or "sim-read" in body or READID in body:
            errors.append("the marker must name the reason and no key: " + body)
    except Exception as err:
        errors.append(f"proxy test crashed: {err!r}")
    finally:
        proc.terminate()
        proc.wait(5)
        upstream.shutdown()

# optional: the pinned binary itself, with the real identity semantics and the proxy in front (SIM_CACHE_WEED_BIN=/path/to/weed)
weed = os.environ.get("SIM_CACHE_WEED_BIN")
if weed:
    live = subprocess.run([sys.executable, "-I", f"{work}/live.py", weed, f"{out}/s3.json", f"{role}/files/tripwire.py"], capture_output=True, text=True, timeout=300)
    print(live.stdout.strip())
    if live.returncode != 0:
        errors.append("live run against the real binary failed:\n" + live.stdout[-1500:] + live.stderr[-1500:])

if errors:
    print("\n".join(errors))
    sys.exit(1)
PY

verify() {
  local dir="$1" outdir="$work/out" pair
  rm -rf "$outdir"; mkdir -p "$outdir"
  for pair in store.service.j2:sim-cache-store.service tripwire.service.j2:sim-cache-tripwire.service tailscaled.service.j2:tailscaled.service \
              trip.service.j2:sim-cache-trip.service trip.path.j2:sim-cache-trip.path s3.json.j2:s3.json \
              trip-failure.service.j2:sim-cache-trip-failure.service allowed-keys.j2:allowed-keys; do
    ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ANSIBLE_NOCOLOR=1 \
      ansible localhost -c local -m ansible.builtin.template \
        -a "src=$dir/templates/${pair%%:*} dest=$outdir/${pair##*:}" \
        -e "@$dir/defaults/main.yml" -e "@$work/vars.json" > "$work/ansible.log" 2>&1 \
      || { cat "$work/ansible.log" >&2; echo "FAIL: ${pair%%:*} did not render" >&2; return 2; }
  done
  python3 -I "$work/check.py" "$dir" "$outdir" "$work"
}

cp "$repo/tests/isolation/lib/sim-cache-live.py" "$work/live.py"
[ -n "${SIM_CACHE_WEED_BIN:-}" ] || echo "skip: SIM_CACHE_WEED_BIN is not set, so the run against the real binary is not part of this suite"
verify "$role" || { echo "FAIL: the role does not meet the sim cache contract" >&2; exit 1; }
echo "ok: units, identities, tasks and the proxy meet the contract"

mutate() {
  local label="$1" file="$2" expr="$3" copy="$work/mut"
  rm -rf "$copy"
  cp -r "$role" "$copy"
  sed -i -e "$expr" "$copy/$file"
  if cmp -s "$role/$file" "$copy/$file"; then
    echo "FAIL: mutation '$label' changed nothing" >&2
    exit 1
  fi
  if SIM_CACHE_WEED_BIN="" verify "$copy" > "$work/mut.log" 2>&1; then
    echo "FAIL: mutation '$label' was not caught" >&2
    exit 1
  fi
  echo "ok: mutation '$label' is rejected: $(grep -v "^$" "$work/mut.log" | head -n1 | cut -c1-200)"
}

mutate "anonymous requests pass" files/tripwire.py 's/return "anonymous request"/return None/'
mutate "unknown keys pass" files/tripwire.py 's/return "unknown access key"/return None/'
mutate "a known user trips the wire" files/tripwire.py 's/if key not in allowed:/if key in allowed:/'
mutate "a query credential passes" files/tripwire.py 's/return "credential in the query string"/return None/'
mutate "a rejected credential is not noticed" files/tripwire.py 's/reject = any(code in buffered for code in REJECT_CODES)/reject = False/'
mutate "no marker written" files/tripwire.py 's/os.replace(temp, self.marker)/pass/'
mutate "a violating request is forwarded" files/tripwire.py 's/^            return self.deny()$/            pass/'
mutate "the host header is rewritten" files/tripwire.py 's/upstream.putrequest(self.command, self.path, skip_host=True, skip_accept_encoding=True)/upstream.putrequest(self.command, self.path, skip_accept_encoding=True)/'
mutate "the store listens on every interface" templates/store.service.j2 's/-ip.bind=127.0.0.1/-ip.bind=0.0.0.0/'
mutate "telemetry left on" templates/store.service.j2 's/-master.telemetry=false/-master.telemetry=true/'
mutate "the embedded iam api is on" templates/store.service.j2 's/-s3.iam=false/-s3.iam=true/'
mutate "a volume port on the cache port" templates/store.service.j2 's/-volume.port={{ sim_cache_service_volume_port }}/-volume.port=8080/'
mutate "the connector gets a tun device route" templates/tailscaled.service.j2 's/--tun=userspace-networking/--tun=tailscale0/'
mutate "the connector offers a local proxy into the tailnet" templates/tailscaled.service.j2 's/--tun=userspace-networking/--tun=userspace-networking --socks5-server=127.0.0.1:1080/'
mutate "the connector survives the tripwire" templates/tailscaled.service.j2 '/^BindsTo=/d'
mutate "the connector only requires the proxy" templates/tailscaled.service.j2 's/^BindsTo=/Requires=/'
mutate "a proxy failure is not a trip" templates/tripwire.service.j2 '/^OnFailure=/d'
mutate "the proxy restarts silently after a crash" templates/tripwire.service.j2 's/^Restart=no/Restart=on-failure/'
mutate "the failure unit leaves no marker" templates/trip-failure.service.j2 's/^ExecStart=\/usr\/bin\/touch/ExecStart=\/usr\/bin\/true/'
mutate "the key ids go on the unit's command line" templates/tripwire.service.j2 's/--allowed-file {{ sim_cache_service_allowed_keys_file }}/--allowed-file {{ sim_cache_service_allowed_keys_file }} --key {{ sim_cache_secrets.reader_key_id }}/'
mutate "the literal reader name as its key id" templates/s3.json.j2 's/"accessKey": "{{ sim_cache_secrets.reader_key_id }}"/"accessKey": "{{ sim_cache_service_reader_user }}"/'
mutate "the literal writer name as its key id" templates/s3.json.j2 's/"accessKey": "{{ sim_cache_secrets.writer_key_id }}"/"accessKey": "{{ sim_cache_service_writer_user }}"/'
mutate "the key file is world readable" tasks/main.yml 's/mode: "0640"/mode: "0644"/'
mutate "two Authorization headers pass" files/tripwire.py 's/return "multiple authorization headers"/return None/'
mutate "a 403 to a HEAD is ignored" files/tripwire.py 's/^                reject = True$/                reject = False/'
mutate "the connector restarts over the marker" templates/tailscaled.service.j2 '/^ConditionPathExists=/d'
mutate "the trip path retriggers while the marker stays" templates/trip.path.j2 's/^PathChanged=/PathExists=/'
mutate "a rearm retriggers the stop" templates/trip.service.j2 '/^ConditionPathExists=/d'
mutate "the marker is published before the stop" templates/trip.service.j2 '/^ExecStart=\/usr\/bin\/systemctl stop/{h;d};/^ExecStart=-/{G}'
mutate "the reader may write" defaults/main.yml 's/^sim_cache_service_reader_actions: .*/sim_cache_service_reader_actions: ["Read:sim-cache", "List:sim-cache", "Write:sim-cache", "Read:sim-control", "List:sim-control"]/'
mutate "the reader may read every bucket" defaults/main.yml 's/^\(sim_cache_service_reader_actions: \["\)Read:sim-cache"/\1Read"/'
mutate "the writer may overwrite the marker" defaults/main.yml 's/^sim_cache_service_writer_actions: .*/sim_cache_service_writer_actions: ["Write:sim-cache", "Write:sim-control", "Read:sim-cache", "List:sim-cache"]/'
mutate "an anonymous identity" templates/s3.json.j2 's/"identities": \[/"identities": [{"name": "anonymous", "actions": ["Read:sim-cache"]},/'
mutate "a misspelt top-level key" templates/s3.json.j2 's/"identities"/"identity"/'
mutate "unpin the store digest" defaults/main.yml 's/^sim_cache_service_seaweed_sha256: .*/sim_cache_service_seaweed_sha256: 0000000000000000000000000000000000000000000000000000000000000000/'
mutate "another cache port" defaults/main.yml 's/^sim_cache_service_listen_port: .*/sim_cache_service_listen_port: 9000/'
mutate "the auth key on argv" tasks/main.yml 's/"--auth-key=file:{{ sim_cache_service_tailscale_authkey_file }}"/"--auth-key={{ sim_cache_secrets.tailscale_auth_key }}"/'
mutate "the auth key file stays behind" tasks/main.yml 's/state: absent/state: touch/'
mutate "drop no_log" tasks/main.yml '0,/^  no_log: true/{//d}'
echo "OK: the sim cache role"
