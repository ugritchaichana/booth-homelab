#!/usr/bin/env python3
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import pwd
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import urllib.parse

EXIT_OK, EXIT_FAILED, EXIT_USAGE, EXIT_REFUSED = 0, 1, 2, 3
NET_KEY = re.compile(r"^net\d+$")
SSH_STATE_KEY = re.compile(r"^(sshkeys|ipconfig\d+|cicustom|ciuser|cipassword|nameserver|searchdomain)$")
FORBIDDEN_KEYS = {
    "qemu": re.compile(r"^(hostpci\d+|usb\d+|virtiofs\d+|serial\d+|parallel\d+|args|hookscript)$"),
    "lxc": re.compile(r"^(mp\d+|dev\d+|features|hookscript|lxc.*)$"),
}


class Refused(Exception):
    pass


class Failed(Exception):
    pass


def stdout_is_journal():
    try:
        info = os.fstat(sys.stdout.fileno())
    except (OSError, ValueError):
        return False
    return os.environ.get("JOURNAL_STREAM") == "%d:%d" % (info.st_dev, info.st_ino)


def log(message):
    print("homelab-template: " + message, flush=True)
    if not stdout_is_journal():
        try:
            subprocess.run(["logger", "-t", "homelab-template", message], check=False, timeout=10)
        except (OSError, subprocess.SubprocessError):
            pass


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run(cmd, check=True, timeout=1800):
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    if check and proc.returncode != 0:
        raise Failed("%s failed rc=%d: %s" % (" ".join(cmd[:3]), proc.returncode, proc.stderr.strip()[:300]))
    return proc


def pvesh_get(path, *extra):
    return json.loads(run(["pvesh", "get", path, *extra, "--output-format", "json"], timeout=120).stdout or "null")


def pvesh_write(verb, path, **options):
    cmd = ["pvesh", verb, path]
    for key, value in options.items():
        cmd += ["--" + key, str(value)]
    run(cmd, timeout=120)


def tool(kind):
    return "qm" if kind == "qemu" else "pct"


def truthy(value):
    return str(value).strip().lower() in ("1", "true")


def split_options(raw):
    options = {}
    for part in str(raw).split(","):
        key, _, value = part.partition("=")
        options[key] = value
    return options


def parse_tags(raw):
    return {t for t in re.split(r"[;,]", str(raw or "")) if t}


def load_config(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def node_path(cfg, kind, vmid):
    return "/nodes/%s/%s/%s" % (cfg["node"], kind, vmid)


class State:
    def __init__(self, cfg, cls):
        self.path = os.path.join(cfg["state_dir"], cls + ".json")
        self.cls = cls
        self.data = None
        if os.path.exists(self.path):
            with open(self.path, encoding="utf-8") as handle:
                self.data = json.load(handle)

    @property
    def exists(self):
        return self.data is not None

    def seed(self, next_n):
        self.data = {"next_n": next_n, "current": None, "previous": None, "verified": {}, "last_build": None}

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(self.data, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, self.path)


def ensure_dirs(cfg):
    for sub in ("", "manifests", "failed"):
        os.makedirs(os.path.join(cfg["state_dir"], sub), mode=0o700, exist_ok=True)


class Lock:
    def __init__(self, cfg):
        ensure_dirs(cfg)
        self.handle = open(os.path.join(cfg["state_dir"], "lock"), "w", encoding="utf-8")
        try:
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise Refused("another homelab-template run holds the lock") from None


def resources(cfg):
    return [r for r in pvesh_get("/cluster/resources", "--type", "vm") if r.get("node") == cfg["node"]]


def block(cfg, cls):
    base = cfg["classes"][cls]["vmid_base"]
    return range(base, base + 100)


def class_guests(cfg, cls):
    return [r for r in resources(cfg) if int(r["vmid"]) in block(cfg, cls)]


def version_tag_number(tags, cfg, cls):
    if cfg["marker_tag"] not in tags or cls not in tags:
        return None
    numbers = [int(t[1:]) for t in tags if re.fullmatch(r"v[0-9]+", t)]
    return numbers[0] if len(numbers) == 1 else None


def tagged_versions(cfg, cls, guests):
    found = {}
    for guest in guests:
        if not guest.get("template"):
            continue
        number = version_tag_number(parse_tags(guest.get("tags")), cfg, cls)
        if number is not None:
            found[number] = guest
    return found


def verified_versions(cfg, cls, guests, state):
    found = {}
    for number, guest in tagged_versions(cfg, cls, guests).items():
        entry = state.data["verified"].get(str(number))
        if entry and int(entry["vmid"]) == int(guest["vmid"]):
            found[number] = guest
    return found


def lvs_rows(cfg):
    out = run(["lvs", "--reportformat", "json", "--units", "b", "-o", "lv_name,origin,data_percent,metadata_percent", cfg["thin_pool"]["vg"]], timeout=120).stdout
    return json.loads(out)["report"][0]["lv"]


def dependents(rows, vmid):
    prefix = "base-%s-disk-" % vmid
    return [r["lv_name"] for r in rows if str(r.get("origin", "")).startswith(prefix)]


def stop_guest(cfg, guest):
    kind, vmid = guest["type"], guest["vmid"]
    if guest.get("status") == "running":
        run([tool(kind), "shutdown", str(vmid), "--timeout", "120", "--forceStop", "1"])


def destroy_guest(guest):
    run([tool(guest["type"]), "destroy", str(guest["vmid"]), "--purge", "1", "--destroy-unreferenced-disks", "1"])


def preflight(cfg):
    limits = cfg["thresholds"]
    pool = [r for r in lvs_rows(cfg) if r["lv_name"] == cfg["thin_pool"]["lv"]]
    if not pool:
        raise Refused("thin pool %s/%s not found" % (cfg["thin_pool"]["vg"], cfg["thin_pool"]["lv"]))
    data, meta = float(pool[0]["data_percent"]), float(pool[0]["metadata_percent"])
    if data > limits["data_percent_max"]:
        raise Refused("thin pool data_percent %.2f is above %s" % (data, limits["data_percent_max"]))
    if meta > limits["metadata_percent_max"]:
        raise Refused("thin pool metadata_percent %.2f is above %s" % (meta, limits["metadata_percent_max"]))
    status = pvesh_get("/nodes/%s/storage/%s/status" % (cfg["node"], cfg["local_storage"]))
    free_gib = float(status["avail"]) / 2**30
    if free_gib < limits["local_free_gib_min"]:
        raise Refused("storage %s has %.1f GiB free, below %s" % (cfg["local_storage"], free_gib, limits["local_free_gib_min"]))
    log("PREFLIGHT ok data_percent=%.2f metadata_percent=%.2f local_free_gib=%.1f" % (data, meta, free_gib))


def prefix_length(cfg):
    return cfg["cidr"].split("/")[1]


def expected_rules(cfg, with_ssh):
    rules = [("group", cfg["group"], "", "", "", 1)]
    if with_ssh:
        rules.append(("in", "ACCEPT", "tcp", "22", cfg["gateway"], 1))
    return sorted(rules)


def normalize_rule(rule):
    extra = tuple(str(rule.get(k, "")) for k in ("dest", "sport", "macro", "iface", "log"))
    base = (str(rule.get("type", "")), str(rule.get("action", "")), str(rule.get("proto", "")), str(rule.get("dport", "")), str(rule.get("source", "")), 1 if truthy(rule.get("enable", 0)) else 0)
    return base + extra if any(extra) else base


def nic_problems(cfg, config):
    problems = []
    nets = sorted(k for k in config if NET_KEY.match(k))
    if nets != ["net0"]:
        problems.append("NICs are %s, wanted exactly net0" % nets)
    for key in nets:
        nic = split_options(config[key])
        if nic.get("bridge") != cfg["vnet"]:
            problems.append("%s bridge is '%s', wanted %s only" % (key, nic.get("bridge"), cfg["vnet"]))
        if not truthy(nic.get("firewall", 0)):
            problems.append("%s firewall is off" % key)
    return problems


def shape_problems(cfg, cls, config, kind):
    problems = []
    for key in sorted(config):
        if FORBIDDEN_KEYS[kind].match(key):
            problems.append("forbidden config key %s" % key)
    spec = cfg["classes"][cls]
    if kind == "lxc":
        if str(config.get("unprivileged", 0)) != "1":
            problems.append("container is not unprivileged")
    else:
        agent = split_options(config.get("agent", "0"))
        if not (config.get("agent") in ("0", 0) or agent.get("enabled") == "0"):
            problems.append("guest agent is not disabled")
        if str(config.get("cpu", "")) != spec["cpu"]:
            problems.append("cpu is '%s', wanted %s" % (config.get("cpu"), spec["cpu"]))
    return problems


def firewall_problems(cfg, kind, vmid, with_ssh, address):
    base = node_path(cfg, kind, vmid) + "/firewall"
    options, rules = pvesh_get(base + "/options") or {}, pvesh_get(base + "/rules") or []
    problems = []
    for key, want in cfg["fw_options"].items():
        have = options.get(key)
        if have is None or str(have).strip().lower() != str(want).strip().lower():
            problems.append("firewall option %s is '%s', wanted %s" % (key, have, want))
    if sorted(normalize_rule(r) for r in rules) != expected_rules(cfg, with_ssh):
        problems.append("firewall rules are not exactly %s" % ("the group rule and the gateway tcp/22 rule" if with_ssh else "the group rule"))
    if kind == "qemu":
        names = [s.get("name") for s in (pvesh_get(base + "/ipset") or [])]
        if with_ssh:
            cidrs = sorted(s.get("cidr", "") for s in (pvesh_get(base + "/ipset/ipfilter-net0") or [])) if "ipfilter-net0" in names else None
            if cidrs is None or [c.split("/")[0] for c in cidrs] != [address]:
                problems.append("ipset ipfilter-net0 is %s, wanted only %s" % (cidrs, address))
        elif "ipfilter-net0" in names:
            problems.append("ipset ipfilter-net0 still exists")
    return problems


def guest_entry(cfg, cls, vmid):
    for entry in class_guests(cfg, cls):
        if int(entry["vmid"]) == int(vmid):
            return entry
    return None


def prestart_readback(cfg, cls, vmid, kind, address, pubkey):
    config = pvesh_get(node_path(cfg, kind, vmid) + "/config")
    problems = nic_problems(cfg, config) + shape_problems(cfg, cls, config, kind)
    prefix = prefix_length(cfg)
    if kind == "lxc":
        nic = split_options(config.get("net0", ""))
        if nic.get("ip") != "%s/%s" % (address, prefix) or nic.get("gw") != cfg["gateway"]:
            problems.append("net0 address is '%s' via '%s', wanted %s/%s via %s" % (nic.get("ip"), nic.get("gw"), address, prefix, cfg["gateway"]))
    else:
        ipconfig = split_options(config.get("ipconfig0", ""))
        if ipconfig.get("ip") != "%s/%s" % (address, prefix) or ipconfig.get("gw") != cfg["gateway"]:
            problems.append("ipconfig0 is '%s', wanted %s/%s via %s" % (config.get("ipconfig0"), address, prefix, cfg["gateway"]))
        if urllib.parse.unquote(str(config.get("sshkeys", ""))).strip() != pubkey.strip():
            problems.append("sshkeys is not the ephemeral build key")
    problems += firewall_problems(cfg, kind, vmid, True, address)
    entry = guest_entry(cfg, cls, vmid)
    if entry is None:
        problems.append("guest is not listed")
    else:
        if entry.get("pool"):
            problems.append("guest is in pool '%s', wanted none" % entry["pool"])
        if entry.get("status") != "stopped":
            problems.append("guest status is '%s', wanted stopped" % entry.get("status"))
        if entry.get("template"):
            problems.append("build guest is already a template")
    if problems:
        raise Failed("pre-start read-back differs: " + "; ".join(problems))
    log("READBACK ok vmid=%s kind=%s before first start: bridge=%s only, firewall on, options and rules exact, shape ok" % (vmid, kind, cfg["vnet"]))


def template_readback(cfg, cls, vmid, kind, tags, converted):
    config = pvesh_get(node_path(cfg, kind, vmid) + "/config")
    problems = nic_problems(cfg, config) + shape_problems(cfg, cls, config, kind)
    for key in sorted(config):
        if SSH_STATE_KEY.match(key):
            problems.append("config still has %s" % key)
    if kind == "lxc" and any(k in split_options(config.get("net0", "")) for k in ("ip", "gw")):
        problems.append("net0 still carries the build address")
    problems += firewall_problems(cfg, kind, vmid, False, "")
    if converted:
        entry = guest_entry(cfg, cls, vmid)
        if entry is None or not entry.get("template"):
            problems.append("guest is not a template")
        elif entry.get("pool") != cfg["pool"]:
            problems.append("template pool is '%s', wanted %s" % (entry.get("pool"), cfg["pool"]))
        elif parse_tags(entry.get("tags")) != tags:
            problems.append("template tags are %s, wanted %s" % (sorted(parse_tags(entry.get("tags"))), sorted(tags)))
    if problems:
        raise Failed("template read-back differs: " + "; ".join(problems))
    log("READBACK ok vmid=%s template: no key, no build address, no inbound rule" % vmid)


def clone_readback(cfg, cls, template_vmid, clone_vmid, kind):
    config = pvesh_get(node_path(cfg, kind, clone_vmid) + "/config")
    problems = nic_problems(cfg, config) + shape_problems(cfg, cls, config, kind)
    for key in sorted(config):
        if SSH_STATE_KEY.match(key):
            problems.append("clone config has %s" % key)
    entry = guest_entry(cfg, cls, clone_vmid)
    if entry is None or entry.get("template"):
        problems.append("clone is missing or is itself a template")
    linked = [r["lv_name"] for r in lvs_rows(cfg) if str(r.get("origin", "")).startswith("base-%s-disk-" % template_vmid) and r["lv_name"].startswith("vm-%s-disk-" % clone_vmid)]
    if not linked:
        problems.append("no thin volume of the clone has the template as origin, so it is not a linked clone")
    if problems:
        raise Failed("clone check differs: " + "; ".join(problems))
    log("VERIFY ok clone=%s is a linked clone of %s (origin %s)" % (clone_vmid, template_vmid, linked[0]))


def require_plain_dir(path, private=False):
    try:
        info = os.lstat(path)
    except OSError as err:
        raise Failed("%s cannot be inspected (%s)" % (path, err.strerror)) from err
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise Failed("%s is a symlink or not a directory, refusing to work inside it" % path)
    if private and (info.st_uid != os.geteuid() or info.st_mode & 0o022):
        raise Failed("%s must be owned by the orchestrator user and not writable by others" % path)


def read_out_file(out, name, limit):
    try:
        dir_fd = os.open(out, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as err:
        raise Failed("%s is missing or a symlink (%s)" % (out, err.strerror)) from err
    try:
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
        except OSError as err:
            raise Failed("%s is missing or not a plain file (%s)" % (name, err.strerror)) from err
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
                raise Failed("%s is not a regular file of at most %d bytes" % (name, limit))
            return os.read(fd, limit + 1)
        finally:
            os.close(fd)
    finally:
        os.close(dir_fd)


def work_build_dir(cfg):
    return os.path.join(cfg["work_dir"], "build")


def reset_build_dir(cfg):
    require_plain_dir(cfg["work_dir"], private=True)
    root = work_build_dir(cfg)
    if os.path.lexists(root):
        require_plain_dir(root)
        shutil.rmtree(root)
    os.mkdir(root, 0o711)
    return root


def guest_owned_dir(path, account):
    os.mkdir(path, 0o700)
    os.chown(path, account.pw_uid, account.pw_gid, follow_symlinks=False)


def prepare_workdir(cfg, cls, build_id, version, address, state):
    spec = cfg["classes"][cls]
    account = pwd.getpwnam(cfg["guest_user"])
    root = reset_build_dir(cfg)
    guest_owned_dir(os.path.join(root, "out"), account)
    guest_owned_dir(os.path.join(root, "ssh"), account)
    bundle = os.path.join(root, "bundle")
    shutil.copytree(cfg["bundle_common_dir"], bundle)
    class_dir = os.path.join(cfg["bundle_root_dir"], cls)
    if os.path.isdir(class_dir):
        shutil.copytree(class_dir, bundle, dirs_exist_ok=True)
    staged = os.path.join(root, "key")
    run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", build_id, "-f", staged], timeout=60)
    key = os.path.join(root, "ssh", "key")
    for suffix in ("", ".pub"):
        os.chown(staged + suffix, account.pw_uid, account.pw_gid, follow_symlinks=False)
        os.rename(staged + suffix, key + suffix)
    previous = ""
    if state.data["current"] is not None:
        source = os.path.join(cfg["state_dir"], "manifests", cls, "v%s.json" % state.data["current"])
        if os.path.exists(source):
            previous = os.path.join(root, "previous-manifest.json")
            shutil.copyfile(source, previous)
            os.chmod(previous, 0o644)
    values = {
        "BUILD_ID": build_id, "CLASS": cls, "VERSION": version, "ADDRESS": address, "LOGIN_USER": spec["login_user"],
        "USE_SUDO": "1" if spec["login_user"] != "root" else "0", "KEY": key, "KNOWN_HOSTS": os.path.join(root, "ssh", "known_hosts"),
        "BUNDLE": bundle, "OUT": os.path.join(root, "out"), "PREVIOUS_MANIFEST": previous,
        "MANIFEST_MAX_BYTES": cfg["manifest_max_bytes"], "SSH_WAIT_SECONDS": cfg["timeouts"]["ssh_wait_seconds"], "RUN_SECONDS": cfg["timeouts"]["run_seconds"],
        "HOOK": spec.get("verify_hook", ""),
    }
    write_params(root, values)
    return open(key + ".pub", encoding="utf-8").read().strip(), key + ".pub"


def write_params(root, values):
    path = os.path.join(root, "params.env")
    with open(path, "w", encoding="utf-8") as handle:
        for name, value in values.items():
            handle.write("%s=%s\n" % (name, value))
    os.chmod(path, 0o644)


def remove_workdir(cfg):
    root = work_build_dir(cfg)
    if os.path.lexists(root):
        require_plain_dir(root)
        shutil.rmtree(root)


def guest_unit(cfg, mode):
    run(["systemctl", "start", "--wait", "%s%s.service" % (cfg["guest_unit_prefix"], mode)], timeout=cfg["timeouts"]["guest_unit_seconds"])


def create_guest(cfg, cls, vmid, kind, name, address, pubfile):
    spec = cfg["classes"][cls]
    gateway, prefix = cfg["gateway"], prefix_length(cfg)
    if kind == "lxc":
        run(["pct", "create", str(vmid), spec["base"], "--hostname", name, "--unprivileged", "1", "--cores", str(spec["cores"]),
             "--memory", str(spec["memory"]), "--swap", "0", "--rootfs", "%s:%s" % (cfg["vm_datastore"], spec["disk_gb"]),
             "--net0", "name=eth0,bridge=%s,firewall=%s,ip=%s/%s,gw=%s" % (cfg["vnet"], cfg["nic_firewall"], address, prefix, gateway),
             "--nameserver", cfg["dns"], "--ssh-public-keys", pubfile, "--onboot", "0", "--start", "0"])
    else:
        run(["qm", "create", str(vmid), "--name", name, "--memory", str(spec["memory"]), "--cores", str(spec["cores"]), "--cpu", spec["cpu"],
             "--agent", "enabled=0", "--ostype", "l26", "--scsihw", "virtio-scsi-single", "--onboot", "0",
             "--scsi0", "%s:0,import-from=%s,discard=on" % (cfg["vm_datastore"], spec["base"]),
             "--net0", "virtio,bridge=%s,firewall=%s" % (cfg["vnet"], cfg["nic_firewall"]),
             "--ide2", "%s:cloudinit" % cfg["vm_datastore"], "--boot", "order=scsi0", "--ciuser", spec["login_user"],
             "--sshkeys", pubfile, "--ipconfig0", "ip=%s/%s,gw=%s" % (address, prefix, gateway), "--nameserver", cfg["dns"]])
        run(["qm", "resize", str(vmid), "scsi0", "%sG" % spec["disk_gb"]])
    base = node_path(cfg, kind, vmid) + "/firewall"
    pvesh_write("set", base + "/options", **cfg["fw_options"])
    pvesh_write("create", base + "/rules", type="group", action=cfg["group"], enable=1)
    pvesh_write("create", base + "/rules", type="in", action="ACCEPT", proto="tcp", dport=22, source=gateway, enable=1)
    if kind == "qemu":
        pvesh_write("create", base + "/ipset", name="ipfilter-net0")
        pvesh_write("create", base + "/ipset/ipfilter-net0", cidr=address)


def strip_for_conversion(cfg, cls, vmid, kind, name, description):
    base = node_path(cfg, kind, vmid) + "/firewall"
    for rule in sorted(pvesh_get(base + "/rules") or [], key=lambda r: -int(r.get("pos", 0))):
        if rule.get("type") == "in":
            pvesh_write("delete", "%s/rules/%s" % (base, rule["pos"]))
    config = pvesh_get(node_path(cfg, kind, vmid) + "/config")
    if kind == "qemu":
        pvesh_write("delete", base + "/ipset/ipfilter-net0", force=1)
        leftover = sorted(k for k in config if SSH_STATE_KEY.match(k))
        run(["qm", "set", str(vmid), "--name", name, "--description", description] + (["--delete", ",".join(leftover)] if leftover else []))
    else:
        run(["pct", "set", str(vmid), "--hostname", name, "--description", description, "--net0", "name=eth0,bridge=%s,firewall=%s,type=veth" % (cfg["vnet"], cfg["nic_firewall"]), "--delete", "nameserver"])


def wanted_tags(cfg, cls, number, current):
    tags = {cfg["marker_tag"], cls, "v%d" % number}
    if current == number:
        tags.add("current")
    return tags


def apply_tags(cfg, cls, state):
    guests = class_guests(cfg, cls)
    versions = verified_versions(cfg, cls, guests, state)
    ordered = sorted(versions.items(), key=lambda item: item[0] == state.data["current"])
    for number, guest in ordered:
        want = wanted_tags(cfg, cls, number, state.data["current"])
        if parse_tags(guest.get("tags")) != want:
            run([tool(guest["type"]), "set", str(guest["vmid"]), "--tags", ";".join(sorted(want))])
            log("TAGS vmid=%s v%d -> %s" % (guest["vmid"], number, ";".join(sorted(want))))


def allocate_vmid(cfg, cls):
    base = cfg["classes"][cls]["vmid_base"]
    used = {int(r["vmid"]) for r in pvesh_get("/cluster/resources", "--type", "vm")}
    for vmid in range(base + 2, base + 100):
        if vmid not in used:
            return vmid
    raise Refused("no free VMID in the %s block %d-%d" % (cls, base, base + 99))


def retain(cfg, cls, state):
    guests = class_guests(cfg, cls)
    keep = {state.data["current"], state.data["previous"]} - {None}
    rows = lvs_rows(cfg)
    templates = {int(g["vmid"]): g for g in guests if g.get("template")}
    kept_vmids = {int(state.data["verified"][str(n)]["vmid"]) for n in keep if str(n) in state.data["verified"]}
    missing = [v for v in kept_vmids if v not in templates]
    if missing or len(kept_vmids) != len(keep):
        raise Failed("retention refused: recorded current or previous version is not a template in the class block (vmids %s)" % sorted(missing))
    numbers = {int(entry["vmid"]): int(n) for n, entry in state.data["verified"].items()}
    victims = {vmid: (numbers.get(vmid), guest) for vmid, guest in templates.items() if vmid not in kept_vmids}
    for number, guest in victims.values():
        found = dependents(rows, guest["vmid"])
        if found:
            log("RETENTION kept vmid=%s: dependent clone volumes %s" % (guest["vmid"], ",".join(found)))
            continue
        destroy_guest(guest)
        log("RETENTION destroyed vmid=%s %s" % (guest["vmid"], "v%d" % number if number else "unverified template"))
        if number is not None:
            state.data["verified"].pop(str(number), None)
            try:
                os.remove(os.path.join(cfg["state_dir"], "manifests", cls, "v%d.json" % number))
            except OSError:
                pass
    state.save()


def diff_summary(old, new):
    return "v%s -> v%s" % (old, new) if old is not None else "first version v%s" % new


def build(cfg, cls):
    spec = cfg["classes"][cls]
    kind = spec["type"]
    lock = Lock(cfg)
    state = State(cfg, cls)
    build_names = re.compile(r"^(build|verify)-%s-v[0-9]+$" % re.escape(cls))
    strangers = [g for g in class_guests(cfg, cls) if not g.get("template") and not (build_names.match(str(g.get("name"))) and not g.get("pool"))]
    if strangers:
        raise Refused("the %s VMID block holds guests that are not build guests of this framework: %s" % (cls, sorted(int(g["vmid"]) for g in strangers)))
    for guest in class_guests(cfg, cls):
        if not guest.get("template"):
            log("LEFTOVER destroying non-template guest vmid=%s status=%s" % (guest["vmid"], guest.get("status")))
            stop_guest(cfg, guest)
            destroy_guest(guest)
    preflight(cfg)
    guests = class_guests(cfg, cls)
    if not state.exists:
        numbers = [n for n in (version_tag_number(parse_tags(g.get("tags")), cfg, cls) for g in guests) if n]
        state.seed(max(numbers, default=0) + 1)
    version = state.data["next_n"]
    state.data["next_n"] = version + 1
    state.save()
    vmid = allocate_vmid(cfg, cls)
    build_id = "%s-v%d-%s-%s" % (cls, version, datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"), secrets.token_hex(4))
    build_name, final_name = "build-%s-v%d" % (cls, version), "tmpl-%s-v%d" % (cls, version)
    address = spec["build_address"]
    log("BUILD start class=%s version=v%d vmid=%s build_id=%s" % (cls, version, vmid, build_id))
    created = converted = False
    clone_vmid = block(cfg, cls)[1]
    try:
        pubkey, pubfile = prepare_workdir(cfg, cls, build_id, version, address, state)
        created = True
        create_guest(cfg, cls, vmid, kind, build_name, address, pubfile)
        prestart_readback(cfg, cls, vmid, kind, address, pubkey)
        log("START vmid=%s" % vmid)
        run([tool(kind), "start", str(vmid)])
        guest_unit(cfg, "build")
        require_plain_dir(cfg["work_dir"], private=True)
        require_plain_dir(work_build_dir(cfg))
        out = os.path.join(work_build_dir(cfg), "out")
        marker = read_out_file(out, "pass", 256)
        if marker != ("PASS %s\n" % build_id).encode():
            raise Failed("pass marker does not carry build id %s" % build_id)
        manifest = read_out_file(out, "manifest.json", cfg["manifest_max_bytes"])
        digest = hashlib.sha256(manifest).hexdigest()
        log("GATE ok build_id=%s manifest_sha256=%s" % (build_id, digest))
        remove_workdir(cfg)
        entry = guest_entry(cfg, cls, vmid)
        stop_guest(cfg, entry)
        description = "class=%s version=%d built=%s manifest_sha256=%s" % (cls, version, now(), digest)
        strip_for_conversion(cfg, cls, vmid, kind, final_name, description)
        template_readback(cfg, cls, vmid, kind, set(), False)
        run([tool(kind), "template", str(vmid)])
        converted = True
        manifest_dir = os.path.join(cfg["state_dir"], "manifests", cls)
        os.makedirs(manifest_dir, mode=0o700, exist_ok=True)
        with open(os.path.join(manifest_dir, "v%d.json" % version), "wb") as handle:
            handle.write(manifest)
        run([tool(kind), "clone", str(vmid), str(clone_vmid), "--full", "0", "--hostname" if kind == "lxc" else "--name", "verify-%s-v%d" % (cls, version)])
        try:
            clone_readback(cfg, cls, vmid, clone_vmid, kind)
            prepare_verify(cfg, cls, version, vmid, clone_vmid)
            guest_unit(cfg, "verify")
        finally:
            remove_workdir(cfg)
            clone = guest_entry(cfg, cls, clone_vmid)
            if clone is not None:
                stop_guest(cfg, clone)
                destroy_guest(clone)
        pvesh_write("set", "/pools/" + cfg["pool"], vms=vmid)
        tags = wanted_tags(cfg, cls, version, None)
        run([tool(kind), "set", str(vmid), "--tags", ";".join(sorted(tags))])
        template_readback(cfg, cls, vmid, kind, tags, True)
    except BaseException as err:
        try:
            remove_workdir(cfg)
        except (Failed, OSError) as cleanup_err:
            log("WORKDIR cleanup refused: %s" % cleanup_err)
        if created:
            leftover = guest_entry(cfg, cls, vmid)
            if leftover is not None:
                try:
                    stop_guest(cfg, leftover)
                    destroy_guest(leftover)
                    log("CLEANUP destroyed vmid=%s after a failed build%s" % (vmid, " (converted, never verified)" if converted else ""))
                except Failed as cleanup_err:
                    log("CLEANUP FAILED vmid=%s: %s" % (vmid, cleanup_err))
        raise
    old = state.data["current"]
    state.data["verified"][str(version)] = {"vmid": vmid, "manifest_sha256": digest, "built": now()}
    if old is not None and old != version:
        state.data["previous"] = old
    state.data["current"] = version
    state.data["last_build"] = now()
    state.save()
    try:
        apply_tags(cfg, cls, state)
    except Failed as err:
        raise Failed("promotion recorded in state but the tag move failed (%s); run: homelab-template repair %s" % (err, cls)) from err
    log("PROMOTED class=%s %s vmid=%s manifest_sha256=%s previous=%s" % (cls, diff_summary(old, version), vmid, digest, state.data["previous"]))
    retain(cfg, cls, state)
    for stale in [os.path.join(cfg["state_dir"], "failed", cls)]:
        if os.path.exists(stale):
            os.remove(stale)
    lock.handle.close()
    return EXIT_OK


def prepare_verify(cfg, cls, version, template_vmid, clone_vmid):
    root = reset_build_dir(cfg)
    values = {"CLASS": cls, "VERSION": version, "TEMPLATE_VMID": template_vmid, "CLONE_VMID": clone_vmid, "HOOK": cfg["classes"][cls].get("verify_hook", "")}
    write_params(root, values)


def rollback(cfg, cls):
    lock = Lock(cfg)
    state = State(cfg, cls)
    if not state.exists or state.data["current"] is None or state.data["previous"] is None:
        raise Refused("class %s has no previous version to roll back to" % cls)
    verified = verified_versions(cfg, cls, class_guests(cfg, cls), state)
    old, target = state.data["current"], state.data["previous"]
    if target not in verified:
        raise Refused("previous version v%s is not a verified template any more" % target)
    state.data["current"], state.data["previous"] = target, old
    state.save()
    apply_tags(cfg, cls, state)
    log("ROLLBACK class=%s current v%s -> v%s previous=v%s vmid=%s" % (cls, old, target, old, verified[target]["vmid"]))
    lock.handle.close()
    return EXIT_OK


def repair(cfg, cls):
    lock = Lock(cfg)
    state = State(cfg, cls)
    if not state.exists:
        raise Refused("class %s has no state to repair from" % cls)
    apply_tags(cfg, cls, state)
    log("REPAIR class=%s tags now follow the recorded current v%s" % (cls, state.data["current"]))
    lock.handle.close()
    return EXIT_OK


def status(cfg, classes):
    code = EXIT_OK
    for cls in classes:
        state = State(cfg, cls)
        guests = class_guests(cfg, cls)
        currents = [g for g in guests if g.get("template") and "current" in parse_tags(g.get("tags")) and version_tag_number(parse_tags(g.get("tags")), cfg, cls) is not None]
        if len(currents) != 1:
            print("class=%s ERROR current-count=%d" % (cls, len(currents)))
            code = EXIT_FAILED
            continue
        guest = currents[0]
        number = version_tag_number(parse_tags(guest.get("tags")), cfg, cls)
        recorded = state.data["current"] if state.exists else None
        previous = state.data["previous"] if state.exists else None
        line = "class=%s current=v%d vmid=%s name=%s previous=%s last_build=%s" % (
            cls, number, guest["vmid"], guest.get("name"), "v%s" % previous if previous is not None else "none", (state.data or {}).get("last_build"))
        if recorded != number:
            line += " MISMATCH recorded=%s" % recorded
            code = EXIT_FAILED
        print(line)
    return code


def record_failure(cfg, cls):
    ensure_dirs(cfg)
    stamp = now()
    with open(os.path.join(cfg["state_dir"], "failed", cls), "w", encoding="utf-8") as handle:
        handle.write(stamp + " build failed; read: journalctl -u homelab-template-build@%s\n" % cls)
    print("<2>homelab-template: BUILD FAILED class=%s at %s; marker %s/failed/%s; read: journalctl -u homelab-template-build@%s" % (cls, stamp, cfg["state_dir"], cls, cls), flush=True)
    return EXIT_OK


def on_term(*_):
    raise KeyboardInterrupt("terminated")


def main():
    parser = argparse.ArgumentParser(prog="homelab-template")
    parser.add_argument("--config", default="/etc/homelab-template/config.json")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("build", "rollback", "repair", "record-failure"):
        sub.add_parser(name).add_argument("cls", metavar="class")
    sub.add_parser("status").add_argument("cls", metavar="class", nargs="?")
    args = parser.parse_args()
    cfg = load_config(args.config)
    if (args.command != "status" or args.cls) and args.cls not in cfg["classes"]:
        print("homelab-template: unknown class %r, known: %s" % (args.cls, ", ".join(sorted(cfg["classes"]))), file=sys.stderr)
        return EXIT_USAGE
    if cfg.get("require_root", True) and os.geteuid() != 0:
        print("homelab-template: must run as root", file=sys.stderr)
        return EXIT_REFUSED
    signal.signal(signal.SIGTERM, on_term)
    try:
        if args.command == "status":
            return status(cfg, [args.cls] if args.cls else sorted(cfg["classes"]))
        return {"build": build, "rollback": rollback, "repair": repair, "record-failure": record_failure}[args.command](cfg, args.cls)
    except Refused as err:
        log("REFUSED %s" % err)
        return EXIT_REFUSED
    except (Failed, KeyboardInterrupt, OSError, ValueError, KeyError, subprocess.SubprocessError) as err:
        log("FAILED %s: %s" % (type(err).__name__, err))
        return EXIT_FAILED


if __name__ == "__main__":
    sys.exit(main())
