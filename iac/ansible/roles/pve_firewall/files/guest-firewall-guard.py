#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import time

EXIT_OK, EXIT_VIOLATION, EXIT_UNVERIFIED = 0, 3, 4
NET_KEY = re.compile(r"^net\d+$")


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60, check=False)


def pvesh(path, *extra):
    proc = run(["pvesh", "get", path, *extra, "--output-format", "json"])
    if proc.returncode != 0:
        raise RuntimeError("pvesh get %s failed rc=%d" % (path, proc.returncode))
    return json.loads(proc.stdout)


def truthy(value):
    return str(value).lower() in ("1", "true")


def nic_options(raw):
    options = {}
    for part in str(raw).split(","):
        key, _, value = part.partition("=")
        options[key] = value
    return options


def check_guest(node, guest, args):
    base = "/nodes/%s/%s/%s" % (node, guest["type"], guest["vmid"])
    config = pvesh(base + "/config")
    nics = [nic_options(v) for k, v in config.items() if NET_KEY.match(k)]
    if not any(nic.get("bridge") == args.vnet for nic in nics):
        return None
    options = pvesh(base + "/firewall/options")
    rules = pvesh(base + "/firewall/rules")
    problems = []
    if not truthy(options.get("enable", 0)):
        problems.append("firewall not enabled")
    if str(options.get("policy_in", "DROP")).upper() != "DROP":
        problems.append("policy_in is not DROP")
    if str(options.get("policy_out", "ACCEPT")).upper() != "DROP":
        problems.append("policy_out is not DROP")
    if not truthy(options.get("ipfilter", 0)):
        problems.append("ipfilter is off")
    if not any(
        r.get("type") == "group" and r.get("action") == args.group and truthy(r.get("enable", 0))
        for r in rules
    ):
        problems.append("group rule %s missing or disabled" % args.group)
    for index, nic in enumerate(nics):
        if not truthy(nic.get("firewall", 0)):
            problems.append("a NIC has firewall=0 (nic %d)" % index)
    return problems


def write_marker(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(time.strftime("%Y-%m-%dT%H:%M:%S%z") + " " + text + "\n")


def clear_marker(path):
    if os.path.exists(path):
        os.remove(path)


def stop_guest(guest):
    tool = "qm" if guest["type"] == "qemu" else "pct"
    proc = run([tool, "stop", str(guest["vmid"])])
    return proc.returncode == 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--node", required=True)
    parser.add_argument("--vnet", required=True)
    parser.add_argument("--group", required=True)
    parser.add_argument("--state-dir", default="/var/lib/homelab/guest-firewall-guard")
    parser.add_argument("--unverified-limit", type=int, default=3)
    args = parser.parse_args()

    os.makedirs(args.state_dir, exist_ok=True)
    lock = open(os.path.join(args.state_dir, "lock"), "w", encoding="utf-8")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("guest-firewall-guard: another run holds the lock, skipping")
        return EXIT_OK

    try:
        resources = [r for r in pvesh("/cluster/resources", "--type", "vm") if r.get("node") == args.node]
    except Exception as err:
        print("guest-firewall-guard: ERROR cannot list guests (%s); no guest was stopped" % err)
        write_marker(os.path.join(args.state_dir, "list-failed"), str(err))
        return EXIT_UNVERIFIED
    clear_marker(os.path.join(args.state_dir, "list-failed"))

    code = EXIT_OK
    for guest in resources:
        vmid = str(guest["vmid"])
        violation = os.path.join(args.state_dir, "violations", vmid)
        unverified = os.path.join(args.state_dir, "unverified", vmid)
        try:
            problems = check_guest(args.node, guest, args)
        except Exception as err:
            count = 1
            if os.path.exists(unverified):
                count = int(open(unverified, encoding="utf-8").read().split()[-1]) + 1
            write_marker(unverified, str(count))
            print("guest-firewall-guard: UNVERIFIED vmid=%s type=%s run=%d/%d (%s)" % (vmid, guest["type"], count, args.unverified_limit, err))
            code = max(code, EXIT_UNVERIFIED)
            if count < args.unverified_limit:
                continue
            problems = ["could not be verified %d runs in a row" % count]
        else:
            clear_marker(unverified)
        if not problems:
            clear_marker(violation)
            continue
        reason = "; ".join(problems)
        write_marker(violation, reason)
        code = max(code, EXIT_VIOLATION)
        if guest.get("status") == "running":
            stopped = stop_guest(guest)
            print("guest-firewall-guard: VIOLATION vmid=%s type=%s %s; %s" % (vmid, guest["type"], reason, "stopped" if stopped else "STOP FAILED"))
            if not stopped:
                code = EXIT_UNVERIFIED
        else:
            print("guest-firewall-guard: VIOLATION vmid=%s type=%s %s; already not running" % (vmid, guest["type"], reason))
    if code == EXIT_OK:
        print("guest-firewall-guard: ok, %d guest(s) checked on %s" % (len(resources), args.node))
    return code


if __name__ == "__main__":
    sys.exit(main())
