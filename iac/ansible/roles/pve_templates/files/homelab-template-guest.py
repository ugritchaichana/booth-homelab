#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import time

PARAM_PATTERNS = {
    "BUILD_ID": r"[A-Za-z0-9._-]{1,96}",
    "ADDRESS": r"[0-9]{1,3}([.][0-9]{1,3}){3}",
    "LOGIN_USER": r"[a-z_][a-z0-9_-]{0,31}",
    "USE_SUDO": r"[01]",
    "MANIFEST_MAX_BYTES": r"[0-9]{1,9}",
    "SSH_WAIT_SECONDS": r"[0-9]{1,5}",
    "RUN_SECONDS": r"[0-9]{1,6}",
}
REMOTE_BUNDLE = "/tmp/homelab-bundle"
REMOTE_OUT = "/var/lib/homelab-build"
DIFF_LINE_LIMIT = 200


def read_params(work):
    values = {}
    with open(os.path.join(work, "build", "params.env"), encoding="utf-8") as handle:
        for line in handle:
            key, sep, value = line.rstrip("\n").partition("=")
            if sep:
                values[key] = value
    for key, pattern in PARAM_PATTERNS.items():
        if key in values and not re.fullmatch(pattern, values[key]):
            raise SystemExit("guest-step: parameter %s is malformed" % key)
    return values


def ssh_command(params, remote):
    return [
        "ssh", "-F", "/dev/null", "-i", params["KEY"], "-l", params["LOGIN_USER"],
        "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "ForwardAgent=no", "-o", "ForwardX11=no",
        "-o", "ClearAllForwardings=yes", "-o", "PermitLocalCommand=no", "-o", "StrictHostKeyChecking=accept-new",
        "-o", "UserKnownHostsFile=" + params["KNOWN_HOSTS"], "-o", "GlobalKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4",
        params["ADDRESS"], remote,
    ]


def privileged(params, command):
    return ("sudo -n " if params["USE_SUDO"] == "1" else "") + command


def wait_for_ssh(params):
    deadline = time.time() + int(params["SSH_WAIT_SECONDS"])
    while time.time() < deadline:
        if subprocess.run(ssh_command(params, "true"), capture_output=True, timeout=30, check=False).returncode == 0:
            return
        time.sleep(3)
    raise SystemExit("guest-step: no ssh answer from the build guest within %s s" % params["SSH_WAIT_SECONDS"])


def push_bundle(params):
    tar = subprocess.Popen(["tar", "-C", params["BUNDLE"], "-cf", "-", "."], stdout=subprocess.PIPE)
    remote = "rm -rf {0} && mkdir -p {0} && tar -xf - -C {0}".format(REMOTE_BUNDLE)
    sent = subprocess.run(ssh_command(params, remote), stdin=tar.stdout, timeout=600, check=False)
    tar.stdout.close()
    if tar.wait() != 0 or sent.returncode != 0:
        raise SystemExit("guest-step: pushing the content bundle failed")


def fetch(params, name, limit):
    remote = privileged(params, "head -c %d %s/%s" % (limit + 1, REMOTE_OUT, name))
    proc = subprocess.run(ssh_command(params, remote), capture_output=True, timeout=120, check=False)
    if proc.returncode != 0 or len(proc.stdout) > limit:
        raise SystemExit("guest-step: could not fetch %s within %d bytes" % (name, limit))
    return proc.stdout


def flatten(node, prefix=""):
    if isinstance(node, dict):
        for key in sorted(node):
            yield from flatten(node[key], "%s.%s" % (prefix, key) if prefix else str(key))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            yield from flatten(item, "%s[%d]" % (prefix, index))
    else:
        yield prefix, node


def clean(text):
    return re.sub(r"[^\x20-\x7e]", "?", str(text))[:200]


def print_manifest_diff(params, manifest):
    previous = params.get("PREVIOUS_MANIFEST", "")
    if not previous or not os.path.exists(previous):
        print("guest-step: MANIFEST-DIFF no previous version; every entry is new")
        return
    with open(previous, encoding="utf-8") as handle:
        old = dict(flatten(json.load(handle)))
    new = dict(flatten(manifest))
    lines = []
    for key in sorted(set(old) | set(new)):
        if old.get(key) != new.get(key):
            lines.append("%s: %s -> %s" % (clean(key), clean(old.get(key, "(absent)")), clean(new.get(key, "(absent)"))))
    print("guest-step: MANIFEST-DIFF %d changed entries against the previous version" % len(lines))
    for line in lines[:DIFF_LINE_LIMIT]:
        print("guest-step: MANIFEST-DIFF " + line)
    if len(lines) > DIFF_LINE_LIMIT:
        print("guest-step: MANIFEST-DIFF %d more lines not shown" % (len(lines) - DIFF_LINE_LIMIT))


def build(work):
    params = read_params(work)
    out = params["OUT"]
    wait_for_ssh(params)
    push_bundle(params)
    ran = subprocess.run(ssh_command(params, privileged(params, "sh %s/run.sh %s" % (REMOTE_BUNDLE, params["BUILD_ID"]))),
                         timeout=int(params["RUN_SECONDS"]), check=False)
    if ran.returncode != 0:
        raise SystemExit("guest-step: in-guest run.sh exited %d, no pass marker is written" % ran.returncode)
    marker = fetch(params, "pass", 128)
    if marker.decode("ascii", "replace").strip() != "PASS " + params["BUILD_ID"]:
        raise SystemExit("guest-step: the pass marker does not carry this build id")
    raw = fetch(params, "manifest.json", int(params["MANIFEST_MAX_BYTES"]))
    manifest = json.loads(raw)
    if not isinstance(manifest, dict):
        raise SystemExit("guest-step: the manifest is not a JSON object")
    print_manifest_diff(params, manifest)
    sealed = subprocess.run(ssh_command(params, privileged(params, "sh %s/seal.sh %s" % (REMOTE_BUNDLE, params["LOGIN_USER"]))), capture_output=True, timeout=120, check=False)
    if "SEAL-OK" not in sealed.stdout.decode("ascii", "replace").splitlines():
        raise SystemExit("guest-step: the guest was not sealed: %s" % clean(sealed.stdout.decode("ascii", "replace")))
    with open(os.path.join(out, "manifest.json"), "wb") as handle:
        handle.write(raw)
    with open(os.path.join(out, "pass"), "w", encoding="ascii") as handle:
        handle.write("PASS %s\n" % params["BUILD_ID"])
    print("guest-step: build %s finished, manifest %d bytes" % (params["BUILD_ID"], len(raw)))


def verify(work):
    params = read_params(work)
    hook = params.get("HOOK", "")
    if not hook:
        print("guest-step: no class verify hook configured; class-agnostic checks only")
        return
    if not (os.path.isabs(hook) and os.access(hook, os.X_OK)):
        raise SystemExit("guest-step: the configured verify hook %s is not an executable file" % hook)
    env = {k: params[k] for k in ("CLASS", "VERSION", "TEMPLATE_VMID", "CLONE_VMID") if k in params}
    env["PATH"] = os.environ.get("PATH", "/usr/bin:/bin")
    if subprocess.run([hook], env=env, timeout=1800, check=False).returncode != 0:
        raise SystemExit("guest-step: the verify hook failed")
    print("guest-step: verify hook passed")


def cleanup(work):
    try:
        params = read_params(work)
    except FileNotFoundError:
        print("guest-step: no work directory, nothing to remove")
        return
    for path in (params.get("KEY"), (params.get("KEY") or "") + ".pub", params.get("KNOWN_HOSTS")):
        if path and os.path.lexists(path):
            os.remove(path)
    print("guest-step: key and known_hosts removed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("build", "verify", "cleanup"))
    parser.add_argument("--work-dir", default="/var/lib/homelab-template-work")
    args = parser.parse_args()
    {"build": build, "verify": verify, "cleanup": cleanup}[args.mode](args.work_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
