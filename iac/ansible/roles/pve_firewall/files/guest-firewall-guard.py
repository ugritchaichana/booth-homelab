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


def is_gateway_ssh_rule(rule, gateway):
    return (
        str(rule.get("type", "")).lower() == "in"
        and str(rule.get("action", "")).upper() == "ACCEPT"
        and str(rule.get("proto", "")).lower() == "tcp"
        and str(rule.get("dport", "")) == "22"
        and str(rule.get("source", "")) == gateway
        and not any(rule.get(key) for key in ("dest", "sport", "macro", "iface"))
    )


def load_policy(path):
    with open(path, encoding="utf-8") as handle:
        vnets = json.load(handle)["vnets"]
    if not isinstance(vnets, dict) or not vnets:
        raise ValueError("policy has no vnets")
    for name, entry in vnets.items():
        if not entry.get("groups"):
            raise ValueError("vnet %s requires at least one group" % name)
    return vnets


def check_guest(node, guest, vnets):
    base = "/nodes/%s/%s/%s" % (node, guest["type"], guest["vmid"])
    config = pvesh(base + "/config")
    nics = [nic_options(v) for k, v in config.items() if NET_KEY.match(k)]
    if not nics:
        return None
    problems = []
    for index, nic in enumerate(nics):
        if nic.get("bridge") not in vnets:
            problems.append("a NIC is on a bridge outside the lab vnets (nic %d)" % index)
    if problems:
        return problems
    entries = [vnets[nic["bridge"]] for nic in nics]
    groups = {group for entry in entries for group in entry["groups"]}
    gateways = {entry["allow_gateway_ssh"] for entry in entries if entry.get("allow_gateway_ssh")}
    options = pvesh(base + "/firewall/options")
    rules = pvesh(base + "/firewall/rules")
    if not truthy(options.get("enable", 0)):
        problems.append("firewall not enabled")
    if str(options.get("policy_in", "DROP")).upper() != "DROP":
        problems.append("policy_in is not DROP")
    if str(options.get("policy_out", "ACCEPT")).upper() != "DROP":
        problems.append("policy_out is not DROP")
    if not truthy(options.get("ipfilter", 0)):
        problems.append("ipfilter is off")
    for group in sorted(groups):
        if not any(r.get("type") == "group" and r.get("action") == group and truthy(r.get("enable", 0)) for r in rules):
            problems.append("group rule %s missing or disabled" % group)
    for rule in rules:
        if not truthy(rule.get("enable", 0)):
            continue
        if rule.get("type") == "group" and rule.get("action") in groups:
            continue
        if any(is_gateway_ssh_rule(rule, gateway) for gateway in gateways):
            continue
        problems.append("enabled rule outside the allowed set (pos %s)" % rule.get("pos", "?"))
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
    parser.add_argument("--policy", required=True)
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
        vnets = load_policy(args.policy)
    except Exception as err:
        print("guest-firewall-guard: ERROR cannot read the policy (%s); no guest was stopped" % err)
        return EXIT_UNVERIFIED

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
            problems = check_guest(args.node, guest, vnets)
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
