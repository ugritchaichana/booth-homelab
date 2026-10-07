#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import urllib.parse

WORLD = os.environ["FAKE_WORLD"]
CALLS = os.environ["FAKE_CALLS"]
tool = os.path.basename(sys.argv[1])
argv = sys.argv[2:]

with open(CALLS, "a", encoding="utf-8") as handle:
    handle.write(tool + " " + " ".join(argv) + "\n")
if any((tool + " " + " ".join(argv)).startswith(p) for p in os.environ.get("FAIL_CALLS", "").split(";") if p):
    sys.exit(2)

if tool == "logger":
    with open(os.environ["FAKE_JOURNAL"], "a", encoding="utf-8") as handle:
        handle.write(argv[-1] + "\n")
    sys.exit(0)

world = json.load(open(WORLD, encoding="utf-8"))
tamper = json.loads(os.environ.get("FAKE_TAMPER", "{}"))
GB = 2**30


def save():
    json.dump(world, open(WORLD, "w", encoding="utf-8"))


def options_of(args):
    parsed, positional, index = {}, [], 0
    while index < len(args):
        if args[index].startswith("--") and index + 1 < len(args):
            parsed[args[index][2:]] = args[index + 1]
            index += 2
        else:
            positional.append(args[index])
            index += 1
    return parsed, positional


def is_build(guest):
    return guest["name"].startswith("build-") and not guest["template"]


def lv_name(vmid, guest):
    return ("base-%s-disk-0" if guest["template"] else "vm-%s-disk-0") % vmid


def new_guest(kind, name, config):
    return {"type": kind, "name": name, "status": "stopped", "template": 0, "pool": "", "tags": "", "config": config,
            "fw_options": {}, "fw_rules": [], "ipsets": {}, "origin": None}


def get_guest(vmid):
    if str(vmid) not in world["guests"]:
        sys.exit(2)
    return world["guests"][str(vmid)]


def view_config(guest):
    config = dict(guest["config"])
    if is_build(guest):
        config.update(tamper.get("config_set", {}))
        for key in tamper.get("config_del", []):
            config.pop(key, None)
    return config


def view_rules(guest):
    rules = [dict(r) for r in guest["fw_rules"]]
    if is_build(guest):
        rules = [r for r in rules if r["type"] not in tamper.get("rules_drop_type", [])]
        for rule in rules:
            rule.update(tamper.get("rules_modify", {}).get(rule["type"], {}))
        rules += [dict(r) for r in tamper.get("rules_add", [])]
    return [dict(r, pos=i) for i, r in enumerate(rules)]


def pvesh():
    verb, path = argv[0], argv[1]
    options, _ = options_of(argv[2:])
    parts = path.strip("/").split("/")
    if verb == "get":
        if path == "/cluster/resources":
            rows = []
            for vmid, guest in world["guests"].items():
                pool = tamper.get("pool", guest["pool"]) if is_build(guest) else guest["pool"]
                rows.append({"vmid": int(vmid), "type": guest["type"], "node": world["node"], "name": guest["name"], "status": guest["status"],
                             "template": guest["template"], "pool": pool, "tags": guest["tags"]})
            print(json.dumps(rows))
        elif parts[:3] == ["nodes", world["node"], "storage"]:
            print(json.dumps({"avail": int(world["local_avail_gib"] * GB), "total": 40 * GB}))
        else:
            guest = get_guest(parts[3])
            tail = "/".join(parts[4:])
            if tail == "config":
                print(json.dumps(view_config(guest)))
            elif tail == "firewall/options":
                shown = dict(guest["fw_options"])
                if is_build(guest):
                    shown.update(tamper.get("options_set", {}))
                    for key in tamper.get("options_del", []):
                        shown.pop(key, None)
                print(json.dumps(shown))
            elif tail == "firewall/rules":
                print(json.dumps(view_rules(guest)))
            elif tail == "firewall/ipset":
                names = [] if (is_build(guest) and tamper.get("ipset_drop")) else sorted(guest["ipsets"])
                print(json.dumps([{"name": n} for n in names]))
            elif tail.startswith("firewall/ipset/"):
                cidrs = guest["ipsets"].get(parts[-1], [])
                if is_build(guest) and "ipset_cidrs" in tamper:
                    cidrs = tamper["ipset_cidrs"]
                print(json.dumps([{"cidr": c} for c in cidrs]))
        return
    if parts[0] == "pools":
        get_guest(options["vms"])["pool"] = parts[1]
    else:
        guest = get_guest(parts[3])
        tail = "/".join(parts[4:])
        if tail == "firewall/options" and verb == "set":
            guest["fw_options"].update({k: v for k, v in options.items()})
        elif tail == "firewall/rules" and verb == "create":
            guest["fw_rules"].append(dict(options))
        elif tail.startswith("firewall/rules/") and verb == "delete":
            del guest["fw_rules"][int(parts[-1])]
        elif tail == "firewall/ipset" and verb == "create":
            guest["ipsets"][options["name"]] = []
        elif tail.startswith("firewall/ipset/") and verb == "create":
            guest["ipsets"][parts[-1]].append(options["cidr"])
        elif tail.startswith("firewall/ipset/") and verb == "delete":
            guest["ipsets"].pop(parts[-1], None)
        else:
            sys.exit(2)
    save()


def guest_tool():
    verb, vmid = argv[0], argv[1]
    options, positional = options_of(argv[2:])
    kind = "qemu" if tool == "qm" else "lxc"
    if verb == "create":
        if str(vmid) in world["guests"]:
            sys.exit(255)
        config = {}
        for key, value in options.items():
            if key in ("ssh-public-keys", "start", "hostname"):
                continue
            config[key] = value
        if kind == "qemu":
            config["net0"] = options["net0"].replace("virtio,", "virtio=AA:BB:CC:00:00:01,", 1)
            config["sshkeys"] = urllib.parse.quote(open(options["sshkeys"], encoding="utf-8").read().strip(), safe="")
            name = options["name"]
        else:
            name = options["hostname"]
            config["ostype"] = "debian"
        world["guests"][str(vmid)] = new_guest(kind, name, config)
    elif verb == "set":
        guest = get_guest(vmid)
        for key, value in options.items():
            if key == "delete":
                for gone in value.split(","):
                    guest["config"].pop(gone, None)
            elif key == "tags":
                guest["tags"] = value
            elif key in ("name", "hostname"):
                guest["name"] = value
            else:
                guest["config"][key] = value
    elif verb == "start":
        get_guest(vmid)["status"] = "running"
    elif verb in ("stop", "shutdown"):
        get_guest(vmid)["status"] = "stopped"
    elif verb == "template":
        guest = get_guest(vmid)
        guest["template"] = 1
        guest["config"]["template"] = "1"
    elif verb == "clone":
        source = get_guest(vmid)
        new = new_guest(kind, options.get("name", options.get("hostname")), json.loads(json.dumps(source["config"])))
        new["config"].pop("template", None)
        new["fw_options"] = dict(source["fw_options"])
        new["fw_rules"] = [dict(r) for r in source["fw_rules"]]
        if options.get("full") == "0" and not os.environ.get("FAKE_CLONE_FULL"):
            new["origin"] = int(vmid)
        world["guests"][positional[0]] = new
    elif verb == "destroy":
        get_guest(vmid)
        del world["guests"][str(vmid)]
    elif verb != "resize":
        sys.exit(2)
    save()


def lvs():
    rows = [{"lv_name": "data", "origin": "", "data_percent": "%.2f" % world["lvs"]["data_percent"], "metadata_percent": "%.2f" % world["lvs"]["metadata_percent"]}]
    for vmid, guest in sorted(world["guests"].items()):
        origin = ""
        if guest["origin"] is not None and str(guest["origin"]) in world["guests"]:
            origin = lv_name(guest["origin"], world["guests"][str(guest["origin"])])
        rows.append({"lv_name": lv_name(vmid, guest), "origin": origin, "data_percent": "1.00", "metadata_percent": ""})
    print(json.dumps({"report": [{"lv": rows}]}))


def systemctl():
    unit = argv[-1]
    mode = re.match(r"homelab-template-guest@(\w+)\.service", unit).group(1)
    work = os.environ["FAKE_WORK_DIR"]
    if mode == "verify":
        sys.exit(subprocess.run([sys.executable, "-I", os.environ["GUEST_STEP"], "verify", "--work-dir", work], check=False).returncode)
    params = dict(line.rstrip("\n").split("=", 1) for line in open(os.path.join(work, "build", "params.env"), encoding="utf-8"))
    scenario, out = os.environ.get("FAKE_GUEST", "pass"), params["OUT"]
    if scenario == "fail":
        sys.exit(1)
    if scenario in ("symlink-out", "symlink-build"):
        victim = os.environ["FAKE_VICTIM"]
        os.makedirs(os.path.join(victim, "out"), exist_ok=True)
        for base in (victim, os.path.join(victim, "out")):
            open(os.path.join(base, "pass"), "w", encoding="ascii").write("PASS %s\n" % params["BUILD_ID"])
            open(os.path.join(base, "manifest.json"), "w", encoding="ascii").write('{"os": "swapped"}')
        target = out if scenario == "symlink-out" else os.path.dirname(out)
        os.rename(target, target + ".gone")
        os.symlink(victim, target)
        sys.exit(0)
    if scenario == "scan":
        guest_root = os.environ["FAKE_SCAN_ROOT"]
        finalized = subprocess.run(["sh", os.environ["FINALIZE_SCRIPT"], params["BUILD_ID"]], capture_output=True, check=False,
                                   env=dict(os.environ, FINALIZE_ROOT=guest_root, FINALIZE_ALLOWLIST="/dev/null"))
        if finalized.returncode != 0:
            sys.exit(1)
        os.environ["FAKE_MANIFEST_FILE"] = os.path.join(guest_root, "var/lib/homelab-build/manifest.json")
    manifest = os.environ.get("FAKE_MANIFEST_FILE")
    body = open(manifest, "rb").read() if manifest else b'{"os": "debian 13"}\n'
    if scenario == "bigmanifest":
        body = b"x" * (int(params["MANIFEST_MAX_BYTES"]) + 1)
    open(os.path.join(out, "manifest.json"), "wb").write(body)
    marker = "PASS %s\n" % ("other-build" if scenario == "wrongid" else params["BUILD_ID"])
    if scenario == "symlink":
        open(os.path.join(work, "elsewhere"), "w", encoding="ascii").write(marker)
        os.symlink(os.path.join(work, "elsewhere"), os.path.join(out, "pass"))
    elif scenario != "nopass":
        open(os.path.join(out, "pass"), "w", encoding="ascii").write(marker)


{"pvesh": pvesh, "qm": guest_tool, "pct": guest_tool, "lvs": lvs, "systemctl": systemctl}[tool]()
