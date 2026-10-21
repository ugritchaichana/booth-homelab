#!/usr/bin/env python3
"""Run the pinned SeaweedFS binary on loopback with the role's s3.json, then drive it directly and through the role's proxy.

usage: sim-cache-live.py <weed binary> <rendered s3.json> <tripwire.py>
Nothing here touches a host: every port is loopback and every directory is a temporary one.
"""
import datetime
import hashlib
import hmac
import http.client
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.error
import urllib.request

weed, s3_json, proxy_script = sys.argv[1:4]
identities = {i["name"]: (i["credentials"][0]["accessKey"], i["credentials"][0]["secretKey"]) for i in json.load(open(s3_json, encoding="utf-8"))["identities"]}
assert all(key != name for name, (key, _) in identities.items()), "an access key id must not be the identity name"
READ, WRITE = identities["sim-read"], identities["sim-write"]
failures = []


def free_pair():
    while True:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        if port > 45000:
            continue
        with socket.socket() as probe:
            if probe.connect_ex(("127.0.0.1", port + 10000)) != 0 and probe.connect_ex(("127.0.0.1", port)) != 0:
                return port


def sign(key, msg):
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()


def s3full(port, method, path, creds=None, body=b"", query=None, host=None):
    query = query or {}
    canon_query = "&".join("%s=%s" % (urllib.parse.quote(k, safe=""), urllib.parse.quote(str(v), safe="")) for k, v in sorted(query.items()))
    now = datetime.datetime.now(datetime.timezone.utc)
    amz, stamp = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
    payload = hashlib.sha256(body).hexdigest()
    headers = {"Host": host or "127.0.0.1:%d" % port, "x-amz-date": amz, "x-amz-content-sha256": payload}
    if creds:
        names = sorted(k.lower() for k in headers)
        canon_headers = "".join("%s:%s\n" % (k, next(v for h, v in headers.items() if h.lower() == k).strip()) for k in names)
        canonical = "\n".join([method, urllib.parse.quote(path, safe="/-_.~"), canon_query, canon_headers, ";".join(names), payload])
        scope = "%s/us-east-1/s3/aws4_request" % stamp
        to_sign = "\n".join(["AWS4-HMAC-SHA256", amz, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        signing = sign(sign(sign(sign(("AWS4" + creds[1]).encode(), stamp), "us-east-1"), "s3"), "aws4_request")
        headers["Authorization"] = "AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s" % (creds[0], scope, ";".join(names), hmac.new(signing, to_sign.encode(), hashlib.sha256).hexdigest())
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
    conn.request(method, path + ("?" + canon_query if canon_query else ""), body=body or None, headers=headers)
    resp = conn.getresponse()
    data = resp.read()
    conn.close()
    code = re.search(rb"<Code>([^<]+)</Code>", data)
    return resp.status, (code.group(1).decode() if code else data.decode(errors="replace")[:80]), data


def s3(*args, **kwargs):
    return s3full(*args, **kwargs)[:2]


def expect(label, got, want):
    ok = got == want
    print(("ok: live %-58s %s" if ok else "FAIL: live %-55s %s want %s") % ((label, got) if ok else (label, got, want)))
    if not ok:
        failures.append(label)


def wait_port(port, seconds=90):
    deadline = time.time() + seconds
    while time.time() < deadline:
        with socket.socket() as sock:
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return True
        time.sleep(0.5)
    return False


with tempfile.TemporaryDirectory() as tmp:
    master, volume, filer, s3p = (free_pair() for _ in range(4))
    server = subprocess.Popen([weed, "server", "-ip=127.0.0.1", "-ip.bind=127.0.0.1", f"-dir={tmp}/data", f"-master.port={master}", "-master.volumeSizeLimitMB=64", "-master.telemetry=false",
                               f"-volume.port={volume}", "-volume.max=12", "-filer", f"-filer.port={filer}", "-filer.tusBasePath=", "-s3", f"-s3.port={s3p}", f"-s3.config={s3_json}", "-s3.iam=false",
                               "-s3.port.iceberg=0", "-s3.port.lance=0", "-s3.autoCreateBucket=false"],
                              cwd=tmp, stdout=open(f"{tmp}/server.log", "w"), stderr=subprocess.STDOUT)
    os.makedirs(f"{tmp}/data", exist_ok=True)
    proxy = None
    try:
        if not wait_port(s3p):
            print(open(f"{tmp}/server.log").read()[-1500:])
            sys.exit("the store did not come up")
        time.sleep(3)
        shell = subprocess.run([weed, "shell", f"-master=127.0.0.1:{master}", f"-filer=127.0.0.1:{filer}"], input="s3.bucket.create -name sim-cache\ns3.bucket.create -name sim-control\ns3.bucket.list\n",
                               capture_output=True, text=True, timeout=60, cwd=tmp)
        expect("the shell created both buckets", sorted(re.findall(r"^\s+(sim-[a-z]+)\s", shell.stdout, re.M)), ["sim-cache", "sim-control"])

        expect("anonymous list", s3(s3p, "GET", "/sim-cache/"), (403, "AccessDenied"))
        expect("anonymous get", s3(s3p, "GET", "/sim-cache/k"), (403, "AccessDenied"))
        expect("anonymous put", s3(s3p, "PUT", "/sim-cache/k", body=b"x"), (403, "AccessDenied"))
        expect("writer put", s3(s3p, "PUT", "/sim-cache/k", WRITE, b"hello"), (200, ""))
        expect("reader get", s3(s3p, "GET", "/sim-cache/k", READ), (200, "hello"))
        expect("reader put", s3(s3p, "PUT", "/sim-cache/k2", READ, b"x"), (403, "AccessDenied"))
        expect("reader delete", s3(s3p, "DELETE", "/sim-cache/k", READ), (403, "AccessDenied"))
        expect("reader list", s3(s3p, "GET", "/sim-cache/", READ, query={"list-type": "2"})[0], 200)
        expect("writer put to the control bucket", s3(s3p, "PUT", "/sim-control/tripwire", WRITE, b"x"), (403, "AccessDenied"))
        expect("reader put to the control bucket", s3(s3p, "PUT", "/sim-control/tripwire", READ, b"x"), (403, "AccessDenied"))
        expect("writer put to another bucket", s3(s3p, "PUT", "/other/k", WRITE, b"x"), (403, "AccessDenied"))
        expect("the old literal key id, right secret", s3(s3p, "GET", "/sim-cache/k", ("sim-read", READ[1])), (403, "InvalidAccessKeyId"))
        expect("unknown key", s3(s3p, "GET", "/sim-cache/k", ("nobody", "x" * 40)), (403, "InvalidAccessKeyId"))
        expect("known key, wrong secret", s3(s3p, "GET", "/sim-cache/k", (READ[0], "y" * 40)), (403, "SignatureDoesNotMatch"))
        expect("writer delete (Write covers it)", s3(s3p, "DELETE", "/sim-cache/k", WRITE)[0], 204)

        # the marker path of the trip service: a PUT to the loopback filer, read back through S3 by the reader
        marker = urllib.request.Request(f"http://127.0.0.1:{filer}/buckets/sim-control/tripwire", data=b"2026-10-21 anonymous request\n", method="PUT", headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            status = urllib.request.urlopen(marker, timeout=30).status
        except urllib.error.HTTPError as err:
            status = "%s %s" % (err.code, err.read()[:200])
        expect("filer accepts the marker", status in (200, 201), True) if not isinstance(status, str) else expect("filer accepts the marker", status, 201)
        expect("reader reads the marker through S3", s3(s3p, "GET", "/sim-control/tripwire", READ), (200, "2026-10-21 anonymous request\n"))
        expect("writer reads the marker through S3", s3(s3p, "GET", "/sim-control/tripwire", WRITE)[0], 200)

        front = free_pair()
        state = f"{tmp}/state"
        os.makedirs(f"{state}/tripwire")
        open(f"{tmp}/allowed-keys", "w", encoding="utf-8").write("".join(f"{name}:{key}\n" for name, (key, _) in identities.items()))
        proxy = subprocess.Popen([sys.executable, "-I", proxy_script, "--listen", f"127.0.0.1:{front}", "--upstream", f"127.0.0.1:{s3p}", "--state-dir", state, "--log-file", f"{tmp}/audit.jsonl",
                                  "--allowed-file", f"{tmp}/allowed-keys"], stdout=subprocess.DEVNULL)
        wait_port(front, 10)
        tripped = lambda: os.path.exists(f"{state}/tripwire/tripped")
        blob = os.urandom(5 << 20)
        expect("proxy: writer uploads 5 MiB", s3(front, "PUT", "/sim-cache/blob", WRITE, blob, host=f"127.0.0.1:{front}"), (200, ""))
        got = s3full(front, "GET", "/sim-cache/blob", READ, host=f"127.0.0.1:{front}")
        expect("proxy: reader gets it back intact", (got[0], hashlib.sha256(got[2]).hexdigest()), (200, hashlib.sha256(blob).hexdigest()))
        expect("proxy: reader put is denied by the store", s3(front, "PUT", "/sim-cache/k3", READ, b"x", host=f"127.0.0.1:{front}"), (403, "AccessDenied"))
        expect("proxy: an authorised denial does not trip the wire", tripped(), False)
        expect("proxy: anonymous is refused", s3(front, "GET", "/sim-cache/", host=f"127.0.0.1:{front}"), (403, "AccessDenied"))
        expect("proxy: anonymous left the marker", tripped(), True)
        os.remove(f"{state}/tripwire/tripped")
        expect("proxy: a wrong secret is reported by the store", s3(front, "GET", "/sim-cache/blob", (READ[0], "y" * 40), host=f"127.0.0.1:{front}"), (403, "SignatureDoesNotMatch"))
        expect("proxy: a wrong secret trips the wire", tripped(), True)
        os.remove(f"{state}/tripwire/tripped")
        expect("proxy: the old literal key id is refused at the proxy", s3(front, "GET", "/sim-cache/blob", ("sim-read", READ[1]), host=f"127.0.0.1:{front}"), (403, "AccessDenied"))
        expect("proxy: the old literal key id trips the wire", tripped(), True)
        os.remove(f"{state}/tripwire/tripped")
        expect("proxy: HEAD with a wrong secret is refused by the store", s3(front, "HEAD", "/sim-cache/blob", (READ[0], "y" * 40), host=f"127.0.0.1:{front}")[0], 403)
        expect("proxy: HEAD with a wrong secret trips the wire", tripped(), True)
        os.remove(f"{state}/tripwire/tripped")
        expect("proxy: a legitimate HEAD does not trip it", (s3(front, "HEAD", "/sim-cache/blob", READ, host=f"127.0.0.1:{front}")[0], tripped()), (200, False))
    finally:
        if proxy:
            proxy.terminate()
        server.terminate()
        try:
            server.wait(20)
        except subprocess.TimeoutExpired:
            server.kill()

if failures:
    sys.exit("live failures: " + ", ".join(failures))
